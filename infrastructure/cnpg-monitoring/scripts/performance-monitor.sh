#!/bin/bash

# CNPG Barman Plugin Performance Monitoring and Comparison Tool
# This script monitors and compares backup performance metrics before and after
# the plugin migration, providing detailed analysis and recommendations

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/var/log/cnpg-performance-monitor.log}"
METRICS_DIR="${METRICS_DIR:-/var/lib/cnpg-metrics}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://prometheus.monitoring.svc.cluster.local:9090}"
BENCHMARK_DURATION="${BENCHMARK_DURATION:-3600}"  # 1 hour default
COMPARISON_PERIOD="${COMPARISON_PERIOD:-7d}"      # 7 days for comparison

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)  echo -e "${GREEN}[INFO]${NC} ${timestamp}: $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} ${timestamp}: $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} ${timestamp}: $message" | tee -a "$LOG_FILE" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} ${timestamp}: $message" | tee -a "$LOG_FILE" ;;
    esac
}

# Query Prometheus for metrics
query_prometheus() {
    local query="$1"
    local timestamp="${2:-$(date +%s)}"
    
    curl -s -G "$PROMETHEUS_URL/api/v1/query" \
        --data-urlencode "query=$query" \
        --data-urlencode "time=$timestamp" | \
        jq -r '.data.result[]? | .value[1]' 2>/dev/null || echo "0"
}

# Query Prometheus for range data
query_prometheus_range() {
    local query="$1"
    local start="$2"
    local end="$3"
    local step="${4:-60s}"
    
    curl -s -G "$PROMETHEUS_URL/api/v1/query_range" \
        --data-urlencode "query=$query" \
        --data-urlencode "start=$start" \
        --data-urlencode "end=$end" \
        --data-urlencode "step=$step" | \
        jq -r '.data.result[]? | .values[]? | join(",")' 2>/dev/null
}

# Calculate statistics from values
calculate_stats() {
    local values=("$@")
    local count=${#values[@]}
    
    if [[ $count -eq 0 ]]; then
        echo "0,0,0,0,0"  # min,max,avg,median,stddev
        return
    fi
    
    # Convert to numbers and sort
    local sorted_values=($(printf '%s\n' "${values[@]}" | sort -n))
    
    local min="${sorted_values[0]}"
    local max="${sorted_values[$((count-1))]}"
    
    # Calculate average
    local sum=0
    for value in "${values[@]}"; do
        sum=$(echo "$sum + $value" | bc -l)
    done
    local avg=$(echo "scale=2; $sum / $count" | bc -l)
    
    # Calculate median
    local median
    if [[ $((count % 2)) -eq 0 ]]; then
        local mid1="${sorted_values[$((count/2-1))]}"
        local mid2="${sorted_values[$((count/2))]}"
        median=$(echo "scale=2; ($mid1 + $mid2) / 2" | bc -l)
    else
        median="${sorted_values[$((count/2))]}"
    fi
    
    # Calculate standard deviation
    local variance=0
    for value in "${values[@]}"; do
        local diff=$(echo "$value - $avg" | bc -l)
        local squared=$(echo "$diff * $diff" | bc -l)
        variance=$(echo "$variance + $squared" | bc -l)
    done
    variance=$(echo "scale=2; $variance / $count" | bc -l)
    local stddev=$(echo "scale=2; sqrt($variance)" | bc -l)
    
    echo "$min,$max,$avg,$median,$stddev"
}

# Collect current performance metrics
collect_current_metrics() {
    local cluster_name="$1"
    local namespace="$2"
    local output_file="$3"
    
    log INFO "Collecting current performance metrics for cluster $cluster_name"
    
    local timestamp=$(date +%s)
    local metrics_json="{"
    
    # Backup performance metrics
    local backup_duration=$(query_prometheus "cnpg_backup_duration_seconds{cnpg_cluster=\"$cluster_name\",namespace=\"$namespace\"}" "$timestamp")
    local backup_size=$(query_prometheus "cnpg_backup_size_bytes{cnpg_cluster=\"$cluster_name\",namespace=\"$namespace\"}" "$timestamp")
    local backup_throughput=$(query_prometheus "rate(cnpg_backup_bytes_transferred{cnpg_cluster=\"$cluster_name\",namespace=\"$namespace\"}[5m])" "$timestamp")
    local compression_ratio=$(query_prometheus "cnpg:backup_compression_ratio{cnpg_cluster=\"$cluster_name\",namespace=\"$namespace\"}" "$timestamp")
    
    # WAL archiving metrics
    local wal_files_pending=$(query_prometheus "cnpg_wal_files_pending{cnpg_cluster=\"$cluster_name\",namespace=\"$namespace\"}" "$timestamp")
    local wal_archive_rate=$(query_prometheus "cnpg:wal_archiving_rate_per_hour{cnpg_cluster=\"$cluster_name\",namespace=\"$namespace\"}" "$timestamp")
    
    # Plugin health metrics
    local plugin_up=$(query_prometheus "up{job=\"cnpg-barman-plugin\",cnpg_cluster=\"$cluster_name\",namespace=\"$namespace\"}" "$timestamp")
    local objectstore_connection=$(query_prometheus "cnpg_objectstore_connection_status{namespace=\"$namespace\"}" "$timestamp")
    
    # Success rates
    local backup_success_rate=$(query_prometheus "cnpg:backup_success_rate_5m{cnpg_cluster=\"$cluster_name\",namespace=\"$namespace\"}" "$timestamp")
    local wal_success_rate=$(query_prometheus "cnpg:wal_archiving_success_rate_5m{cnpg_cluster=\"$cluster_name\",namespace=\"$namespace\"}" "$timestamp")
    
    # Build JSON
    metrics_json+='"timestamp": "'$(date -u -d @$timestamp +%Y-%m-%dT%H:%M:%SZ)'",'
    metrics_json+='"cluster": "'$cluster_name'",'
    metrics_json+='"namespace": "'$namespace'",'
    metrics_json+='"backup_duration_seconds": '$backup_duration','
    metrics_json+='"backup_size_bytes": '$backup_size','
    metrics_json+='"backup_throughput_bps": '$backup_throughput','
    metrics_json+='"compression_ratio": '$compression_ratio','
    metrics_json+='"wal_files_pending": '$wal_files_pending','
    metrics_json+='"wal_archive_rate_per_hour": '$wal_archive_rate','
    metrics_json+='"plugin_up": '$plugin_up','
    metrics_json+='"objectstore_connection": '$objectstore_connection','
    metrics_json+='"backup_success_rate": '$backup_success_rate','
    metrics_json+='"wal_success_rate": '$wal_success_rate
    metrics_json+='}'
    
    echo "$metrics_json" | jq '.' > "$output_file"
    
    log INFO "Metrics collected and saved to $output_file"
}

# Collect historical performance data
collect_historical_metrics() {
    local cluster_name="$1"
    local namespace="$2"
    local period="$3"
    local output_file="$4"
    
    log INFO "Collecting historical metrics for cluster $cluster_name (period: $period)"
    
    local end_time=$(date +%s)
    local start_time
    
    case "$period" in
        "1h") start_time=$((end_time - 3600)) ;;
        "6h") start_time=$((end_time - 21600)) ;;
        "1d") start_time=$((end_time - 86400)) ;;
        "7d") start_time=$((end_time - 604800)) ;;
        "30d") start_time=$((end_time - 2592000)) ;;
        *) 
            log ERROR "Invalid period: $period"
            return 1
            ;;
    esac
    
    # Collect range data for key metrics
    local backup_durations=($(query_prometheus_range "cnpg_backup_duration_seconds{cnpg_cluster=\"$cluster_name\",namespace=\"$namespace\"}" "$start_time" "$end_time" "300s" | cut -d',' -f2))
    local backup_throughputs=($(query_prometheus_range "rate(cnpg_backup_bytes_transferred{cnpg_cluster=\"$cluster_name\",namespace=\"$namespace\"}[5m])" "$start_time" "$end_time" "300s" | cut -d',' -f2))
    local wal_pending=($(query_prometheus_range "cnpg_wal_files_pending{cnpg_cluster=\"$cluster_name\",namespace=\"$namespace\"}" "$start_time" "$end_time" "60s" | cut -d',' -f2))
    
    # Calculate statistics
    local duration_stats=$(calculate_stats "${backup_durations[@]}")
    local throughput_stats=$(calculate_stats "${backup_throughputs[@]}")
    local wal_stats=$(calculate_stats "${wal_pending[@]}")
    
    # Build JSON with statistics
    local metrics_json="{"
    metrics_json+='"period": "'$period'",'
    metrics_json+='"cluster": "'$cluster_name'",'
    metrics_json+='"namespace": "'$namespace'",'
    metrics_json+='"start_time": "'$(date -u -d @$start_time +%Y-%m-%dT%H:%M:%SZ)'",'
    metrics_json+='"end_time": "'$(date -u -d @$end_time +%Y-%m-%dT%H:%M:%SZ)'",'
    metrics_json+='"backup_duration_stats": {'
    metrics_json+='"min": '$(echo "$duration_stats" | cut -d',' -f1)','
    metrics_json+='"max": '$(echo "$duration_stats" | cut -d',' -f2)','
    metrics_json+='"avg": '$(echo "$duration_stats" | cut -d',' -f3)','
    metrics_json+='"median": '$(echo "$duration_stats" | cut -d',' -f4)','
    metrics_json+='"stddev": '$(echo "$duration_stats" | cut -d',' -f5)
    metrics_json+='},'
    metrics_json+='"backup_throughput_stats": {'
    metrics_json+='"min": '$(echo "$throughput_stats" | cut -d',' -f1)','
    metrics_json+='"max": '$(echo "$throughput_stats" | cut -d',' -f2)','
    metrics_json+='"avg": '$(echo "$throughput_stats" | cut -d',' -f3)','
    metrics_json+='"median": '$(echo "$throughput_stats" | cut -d',' -f4)','
    metrics_json+='"stddev": '$(echo "$throughput_stats" | cut -d',' -f5)
    metrics_json+='},'
    metrics_json+='"wal_pending_stats": {'
    metrics_json+='"min": '$(echo "$wal_stats" | cut -d',' -f1)','
    metrics_json+='"max": '$(echo "$wal_stats" | cut -d',' -f2)','
    metrics_json+='"avg": '$(echo "$wal_stats" | cut -d',' -f3)','
    metrics_json+='"median": '$(echo "$wal_stats" | cut -d',' -f4)','
    metrics_json+='"stddev": '$(echo "$wal_stats" | cut -d',' -f5)
    metrics_json+='}'
    metrics_json+='}'
    
    echo "$metrics_json" | jq '.' > "$output_file"
    
    log INFO "Historical metrics collected and saved to $output_file"
}

# Compare metrics between two periods
compare_metrics() {
    local before_file="$1"
    local after_file="$2"
    local output_file="$3"
    
    log INFO "Comparing metrics: $before_file vs $after_file"
    
    if [[ ! -f "$before_file" ]] || [[ ! -f "$after_file" ]]; then
        log ERROR "Metrics files not found"
        return 1
    fi
    
    # Extract key metrics for comparison
    local before_duration_avg=$(jq -r '.backup_duration_stats.avg // 0' "$before_file")
    local after_duration_avg=$(jq -r '.backup_duration_stats.avg // 0' "$after_file")
    
    local before_throughput_avg=$(jq -r '.backup_throughput_stats.avg // 0' "$before_file")
    local after_throughput_avg=$(jq -r '.backup_throughput_stats.avg // 0' "$after_file")
    
    local before_wal_avg=$(jq -r '.wal_pending_stats.avg // 0' "$before_file")
    local after_wal_avg=$(jq -r '.wal_pending_stats.avg // 0' "$after_file")
    
    # Calculate percentage changes
    local duration_change=$(echo "scale=2; (($after_duration_avg - $before_duration_avg) / $before_duration_avg) * 100" | bc -l 2>/dev/null || echo "0")
    local throughput_change=$(echo "scale=2; (($after_throughput_avg - $before_throughput_avg) / $before_throughput_avg) * 100" | bc -l 2>/dev/null || echo "0")
    local wal_change=$(echo "scale=2; (($after_wal_avg - $before_wal_avg) / $before_wal_avg) * 100" | bc -l 2>/dev/null || echo "0")
    
    # Determine improvement status
    local duration_improvement="neutral"
    local throughput_improvement="neutral"
    local wal_improvement="neutral"
    
    if (( $(echo "$duration_change < -5" | bc -l) )); then
        duration_improvement="improved"
    elif (( $(echo "$duration_change > 5" | bc -l) )); then
        duration_improvement="degraded"
    fi
    
    if (( $(echo "$throughput_change > 5" | bc -l) )); then
        throughput_improvement="improved"
    elif (( $(echo "$throughput_change < -5" | bc -l) )); then
        throughput_improvement="degraded"
    fi
    
    if (( $(echo "$wal_change < -10" | bc -l) )); then
        wal_improvement="improved"
    elif (( $(echo "$wal_change > 10" | bc -l) )); then
        wal_improvement="degraded"
    fi
    
    # Generate comparison report
    local comparison_json="{"
    comparison_json+='"comparison_timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",'
    comparison_json+='"before_period": '$(jq '.period' "$before_file")','
    comparison_json+='"after_period": '$(jq '.period' "$after_file")','
    comparison_json+='"backup_duration": {'
    comparison_json+='"before_avg": '$before_duration_avg','
    comparison_json+='"after_avg": '$after_duration_avg','
    comparison_json+='"change_percent": '$duration_change','
    comparison_json+='"improvement": "'$duration_improvement'"'
    comparison_json+='},'
    comparison_json+='"backup_throughput": {'
    comparison_json+='"before_avg": '$before_throughput_avg','
    comparison_json+='"after_avg": '$after_throughput_avg','
    comparison_json+='"change_percent": '$throughput_change','
    comparison_json+='"improvement": "'$throughput_improvement'"'
    comparison_json+='},'
    comparison_json+='"wal_pending": {'
    comparison_json+='"before_avg": '$before_wal_avg','
    comparison_json+='"after_avg": '$after_wal_avg','
    comparison_json+='"change_percent": '$wal_change','
    comparison_json+='"improvement": "'$wal_improvement'"'
    comparison_json+='},'
    
    # Overall assessment
    local improvements=0
    local degradations=0
    
    [[ "$duration_improvement" == "improved" ]] && improvements=$((improvements + 1))
    [[ "$throughput_improvement" == "improved" ]] && improvements=$((improvements + 1))
    [[ "$wal_improvement" == "improved" ]] && improvements=$((improvements + 1))
    
    [[ "$duration_improvement" == "degraded" ]] && degradations=$((degradations + 1))
    [[ "$throughput_improvement" == "degraded" ]] && degradations=$((degradations + 1))
    [[ "$wal_improvement" == "degraded" ]] && degradations=$((degradations + 1))
    
    local overall_status="neutral"
    if [[ $improvements -gt $degradations ]]; then
        overall_status="improved"
    elif [[ $degradations -gt $improvements ]]; then
        overall_status="degraded"
    fi
    
    comparison_json+='"overall_assessment": {'
    comparison_json+='"status": "'$overall_status'",'
    comparison_json+='"improvements": '$improvements','
    comparison_json+='"degradations": '$degradations
    comparison_json+='}'
    comparison_json+='}'
    
    echo "$comparison_json" | jq '.' > "$output_file"
    
    log INFO "Comparison report generated: $output_file"
    
    # Display summary
    log INFO "Performance Comparison Summary:"
    log INFO "  Backup Duration: ${duration_change}% ($duration_improvement)"
    log INFO "  Backup Throughput: ${throughput_change}% ($throughput_improvement)"
    log INFO "  WAL Pending: ${wal_change}% ($wal_improvement)"
    log INFO "  Overall Status: $overall_status"
}

# Generate performance recommendations
generate_recommendations() {
    local comparison_file="$1"
    local output_file="$2"
    
    log INFO "Generating performance recommendations based on $comparison_file"
    
    if [[ ! -f "$comparison_file" ]]; then
        log ERROR "Comparison file not found: $comparison_file"
        return 1
    fi
    
    local duration_improvement=$(jq -r '.backup_duration.improvement' "$comparison_file")
    local throughput_improvement=$(jq -r '.backup_throughput.improvement' "$comparison_file")
    local wal_improvement=$(jq -r '.wal_pending.improvement' "$comparison_file")
    local overall_status=$(jq -r '.overall_assessment.status' "$comparison_file")
    
    local recommendations='[]'
    
    # Duration-based recommendations
    if [[ "$duration_improvement" == "degraded" ]]; then
        recommendations=$(echo "$recommendations" | jq '. += [{"category": "backup_duration", "priority": "high", "recommendation": "Backup duration has increased significantly. Consider increasing backup parallelism or checking storage performance.", "action": "Review ObjectStore configuration and increase backup jobs parameter"}]')
    elif [[ "$duration_improvement" == "improved" ]]; then
        recommendations=$(echo "$recommendations" | jq '. += [{"category": "backup_duration", "priority": "info", "recommendation": "Backup duration has improved. The migration is showing positive results.", "action": "Monitor to ensure sustained improvement"}]')
    fi
    
    # Throughput-based recommendations
    if [[ "$throughput_improvement" == "degraded" ]]; then
        recommendations=$(echo "$recommendations" | jq '. += [{"category": "backup_throughput", "priority": "high", "recommendation": "Backup throughput has decreased. Check network connectivity and S3 endpoint performance.", "action": "Verify S3 credentials, endpoint configuration, and network policies"}]')
    elif [[ "$throughput_improvement" == "improved" ]]; then
        recommendations=$(echo "$recommendations" | jq '. += [{"category": "backup_throughput", "priority": "info", "recommendation": "Backup throughput has improved. The plugin is performing well.", "action": "Consider documenting current configuration as best practice"}]')
    fi
    
    # WAL-based recommendations
    if [[ "$wal_improvement" == "degraded" ]]; then
        recommendations=$(echo "$recommendations" | jq '. += [{"category": "wal_archiving", "priority": "critical", "recommendation": "WAL files are accumulating. This could lead to disk space issues and potential data loss.", "action": "Check WAL archiving configuration and ObjectStore connectivity immediately"}]')
    elif [[ "$wal_improvement" == "improved" ]]; then
        recommendations=$(echo "$recommendations" | jq '. += [{"category": "wal_archiving", "priority": "info", "recommendation": "WAL archiving performance has improved.", "action": "Current configuration is working well"}]')
    fi
    
    # Overall recommendations
    if [[ "$overall_status" == "degraded" ]]; then
        recommendations=$(echo "$recommendations" | jq '. += [{"category": "overall", "priority": "high", "recommendation": "Overall performance has degraded after migration. Consider rollback if issues persist.", "action": "Review all plugin configurations and compare with pre-migration settings"}]')
    elif [[ "$overall_status" == "improved" ]]; then
        recommendations=$(echo "$recommendations" | jq '. += [{"category": "overall", "priority": "info", "recommendation": "Migration has improved backup performance. Consider applying similar configuration to other clusters.", "action": "Document successful configuration and plan broader rollout"}]')
    else
        recommendations=$(echo "$recommendations" | jq '. += [{"category": "overall", "priority": "low", "recommendation": "Performance is stable after migration.", "action": "Continue monitoring for any changes in performance trends"}]')
    fi
    
    # Generate final recommendations report
    local report_json="{"
    report_json+='"generated_at": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",'
    report_json+='"based_on_comparison": "'$(basename "$comparison_file")'",'
    report_json+='"recommendations": '$recommendations
    report_json+='}'
    
    echo "$report_json" | jq '.' > "$output_file"
    
    log INFO "Recommendations report generated: $output_file"
    
    # Display recommendations
    echo "$recommendations" | jq -r '.[] | "  [\(.priority | ascii_upcase)] \(.category): \(.recommendation)"'
}

# Run performance benchmark
run_performance_benchmark() {
    local cluster_name="$1"
    local namespace="$2"
    local duration="$3"
    
    log INFO "Running performance benchmark for cluster $cluster_name (duration: ${duration}s)"
    
    local benchmark_start=$(date +%s)
    local benchmark_end=$((benchmark_start + duration))
    local metrics_samples=()
    local sample_interval=60  # Sample every minute
    
    log INFO "Benchmark started, will run until $(date -d @$benchmark_end)"
    
    while [[ $(date +%s) -lt $benchmark_end ]]; do
        local current_time=$(date +%s)
        
        # Collect sample metrics
        local backup_duration=$(query_prometheus "cnpg_backup_duration_seconds{cnpg_cluster=\"$cluster_name\",namespace=\"$namespace\"}")
        local backup_throughput=$(query_prometheus "rate(cnpg_backup_bytes_transferred{cnpg_cluster=\"$cluster_name\",namespace=\"$namespace\"}[5m])")
        local wal_pending=$(query_prometheus "cnpg_wal_files_pending{cnpg_cluster=\"$cluster_name\",namespace=\"$namespace\"}")
        
        # Store sample
        local sample="{"
        sample+='"timestamp": '$current_time','
        sample+='"backup_duration": '$backup_duration','
        sample+='"backup_throughput": '$backup_throughput','
        sample+='"wal_pending": '$wal_pending
        sample+='}'
        
        metrics_samples+=("$sample")
        
        log DEBUG "Sample collected: duration=${backup_duration}s, throughput=${backup_throughput}bps, wal_pending=${wal_pending}"
        
        sleep $sample_interval
    done
    
    # Generate benchmark report
    local benchmark_file="$METRICS_DIR/benchmark-${cluster_name}-$(date +%Y%m%d-%H%M%S).json"
    local report_json="{"
    report_json+='"benchmark_info": {'
    report_json+='"cluster": "'$cluster_name'",'
    report_json+='"namespace": "'$namespace'",'
    report_json+='"start_time": "'$(date -u -d @$benchmark_start +%Y-%m-%dT%H:%M:%SZ)'",'
    report_json+='"end_time": "'$(date -u -d @$benchmark_end +%Y-%m-%dT%H:%M:%SZ)'",'
    report_json+='"duration_seconds": '$duration','
    report_json+='"sample_interval": '$sample_interval
    report_json+='},'
    report_json+='"samples": ['
    
    local first=true
    for sample in "${metrics_samples[@]}"; do
        [[ "$first" == "true" ]] && first=false || report_json+=','
        report_json+="$sample"
    done
    
    report_json+=']}'
    
    echo "$report_json" | jq '.' > "$benchmark_file"
    
    log INFO "Benchmark completed. Report saved to: $benchmark_file"
    echo "$benchmark_file"
}

# Main performance monitoring function
main() {
    # Ensure directories exist
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$METRICS_DIR"
    
    log INFO "CNPG Performance Monitoring starting on $(hostname)"
    log INFO "Metrics directory: $METRICS_DIR"
    log INFO "Prometheus URL: $PROMETHEUS_URL"
    
    # Check prerequisites
    if ! command -v curl &> /dev/null; then
        log ERROR "curl not found"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log ERROR "jq not found"
        exit 1
    fi
    
    if ! command -v bc &> /dev/null; then
        log ERROR "bc not found"
        exit 1
    fi
    
    # Test Prometheus connectivity
    if ! curl -s "$PROMETHEUS_URL/api/v1/query?query=up" | jq -e '.status == "success"' &>/dev/null; then
        log ERROR "Cannot connect to Prometheus at $PROMETHEUS_URL"
        exit 1
    fi
    
    local action="${1:-collect}"
    local cluster_name="${2:-}"
    local namespace="${3:-}"
    
    case "$action" in
        "collect")
            if [[ -z "$cluster_name" ]] || [[ -z "$namespace" ]]; then
                log ERROR "Usage: $0 collect <cluster_name> <namespace>"
                exit 1
            fi
            
            local output_file="$METRICS_DIR/current-${cluster_name}-$(date +%Y%m%d-%H%M%S).json"
            collect_current_metrics "$cluster_name" "$namespace" "$output_file"
            ;;
            
        "historical")
            if [[ -z "$cluster_name" ]] || [[ -z "$namespace" ]]; then
                log ERROR "Usage: $0 historical <cluster_name> <namespace> [period]"
                exit 1
            fi
            
            local period="${4:-$COMPARISON_PERIOD}"
            local output_file="$METRICS_DIR/historical-${cluster_name}-${period}-$(date +%Y%m%d-%H%M%S).json"
            collect_historical_metrics "$cluster_name" "$namespace" "$period" "$output_file"
            ;;
            
        "compare")
            local before_file="$4"
            local after_file="$5"
            
            if [[ -z "$before_file" ]] || [[ -z "$after_file" ]]; then
                log ERROR "Usage: $0 compare <cluster_name> <namespace> <before_file> <after_file>"
                exit 1
            fi
            
            local output_file="$METRICS_DIR/comparison-${cluster_name}-$(date +%Y%m%d-%H%M%S).json"
            compare_metrics "$before_file" "$after_file" "$output_file"
            
            # Generate recommendations
            local recommendations_file="$METRICS_DIR/recommendations-${cluster_name}-$(date +%Y%m%d-%H%M%S).json"
            generate_recommendations "$output_file" "$recommendations_file"
            ;;
            
        "benchmark")
            if [[ -z "$cluster_name" ]] || [[ -z "$namespace" ]]; then
                log ERROR "Usage: $0 benchmark <cluster_name> <namespace> [duration]"
                exit 1
            fi
            
            local duration="${4:-$BENCHMARK_DURATION}"
            run_performance_benchmark "$cluster_name" "$namespace" "$duration"
            ;;
            
        *)
            log ERROR "Invalid action: $action"
            log INFO "Available actions: collect, historical, compare, benchmark"
            exit 1
            ;;
    esac
    
    log INFO "Performance monitoring completed successfully"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi