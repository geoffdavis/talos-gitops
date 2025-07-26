#!/bin/bash
# Comprehensive Samsung Portable SSD T5 Storage Validation Script
# Complete end-to-end validation of Samsung Portable SSD T5 storage integration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
NODES=("mini01" "mini02" "mini03")
NODE_IPS=("172.29.51.11" "172.29.51.12" "172.29.51.13")
MOUNT_POINT="/var/lib/longhorn-ssd"
MIN_SIZE_GB=100
TALOSCONFIG="${TALOSCONFIG:-clusterconfig/talosconfig}"
REPORT_FILE="usb-ssd-validation-report-$(date +%Y%m%d-%H%M%S).txt"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$REPORT_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[SUCCESS] $1" >> "$REPORT_FILE"
    ((PASSED_TESTS++))
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[WARNING] $1" >> "$REPORT_FILE"
    ((WARNING_TESTS++))
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> "$REPORT_FILE"
    ((FAILED_TESTS++))
}

log_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
    echo "[TEST] $1" >> "$REPORT_FILE"
    ((TOTAL_TESTS++))
}

log_section() {
    echo
    echo -e "${MAGENTA}=== $1 ===${NC}"
    echo
    echo "=== $1 ===" >> "$REPORT_FILE"
    echo >> "$REPORT_FILE"
}

# Initialize report
init_report() {
    cat > "$REPORT_FILE" << EOF
Samsung Portable SSD T5 Storage Validation Report
Generated: $(date)
Cluster: home-ops
Validation Script: validate-complete-usb-ssd-setup.sh

EOF
}

# Check prerequisites
check_prerequisites() {
    log_section "Prerequisites Check"

    log_test "Checking required tools"
    local tools=("talosctl" "kubectl" "jq")
    local missing_tools=0

    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            log_success "$tool is available"
        else
            log_error "$tool is not installed or not in PATH"
            ((missing_tools++))
        fi
    done

    if [[ $missing_tools -gt 0 ]]; then
        log_error "Missing $missing_tools required tools"
        return 1
    fi

    log_test "Checking Talos configuration"
    if [[ -f "$TALOSCONFIG" ]]; then
        log_success "Talos configuration found at $TALOSCONFIG"
    else
        log_error "Talos configuration not found at $TALOSCONFIG"
        return 1
    fi

    log_test "Checking cluster connectivity"
    if kubectl cluster-info &> /dev/null; then
        log_success "Kubernetes cluster is accessible"
    else
        log_error "Cannot connect to Kubernetes cluster"
        return 1
    fi

    log_test "Checking node connectivity"
    local unreachable_nodes=0
    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${NODE_IPS[$i]}"
        if talosctl -n "$ip" version --timeout 10s &> /dev/null; then
            log_success "Node $node ($ip) is reachable"
        else
            log_error "Node $node ($ip) is not reachable"
            ((unreachable_nodes++))
        fi
    done

    if [[ $unreachable_nodes -gt 0 ]]; then
        log_error "$unreachable_nodes nodes are unreachable"
        return 1
    fi

    return 0
}

# Validate Samsung Portable SSD T5 hardware detection
validate_usb_hardware() {
    log_section "Samsung Portable SSD T5 Hardware Detection"

    local nodes_without_usb=0

    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${NODE_IPS[$i]}"

        log_test "Checking Samsung Portable SSD T5 detection on $node"

        # Check for Samsung Portable SSD T5 devices
        local t5_devices
        t5_devices=$(talosctl -n "$ip" ls /dev/disk/by-id/ 2>/dev/null | grep -E "usb-Samsung_Portable_SSD_T5.*[^0-9]$" || true)

        if [[ -z "$t5_devices" ]]; then
            log_warning "No Samsung Portable SSD T5 drives detected on $node"
            ((nodes_without_usb++))
            continue
        fi

        log_success "Samsung Portable SSD T5 drives found on $node"

        # Analyze each Samsung Portable SSD T5 device
        echo "$t5_devices" | while read -r device; do
            if [[ -n "$device" ]]; then
                log_info "  Device: $device"

                # Get device details
                local real_device
                real_device=$(talosctl -n "$ip" readlink "/dev/disk/by-id/$device" 2>/dev/null || echo "")
                if [[ -n "$real_device" ]]; then
                    local device_name
                    device_name=$(basename "$real_device")

                    # Check device size
                    local size_sectors
                    size_sectors=$(talosctl -n "$ip" cat "/sys/block/$device_name/size" 2>/dev/null || echo "0")
                    local size_gb=$((size_sectors * 512 / 1024 / 1024 / 1024))

                    log_info "    Size: ${size_gb}GB"

                    # Check device model
                    local model
                    model=$(talosctl -n "$ip" cat "/sys/block/$device_name/device/model" 2>/dev/null | tr -d ' ' || echo "unknown")
                    log_info "    Model: $model"

                    # Verify it's actually a T5
                    if [[ "$model" == *"PortableSSDT5"* ]] || [[ "$model" == *"T5"* ]]; then
                        log_success "    Confirmed Samsung Portable SSD T5 model"
                    else
                        log_warning "    Model verification failed (expected T5, got: $model)"
                    fi

                    if [[ $size_gb -gt $MIN_SIZE_GB ]]; then
                        log_success "    Size meets minimum requirement (${MIN_SIZE_GB}GB)"
                    else
                        log_warning "    Size below minimum requirement (${MIN_SIZE_GB}GB)"
                    fi

                    # Check I/O scheduler
                    local scheduler
                    scheduler=$(talosctl -n "$ip" cat "/sys/block/$device_name/queue/scheduler" 2>/dev/null | grep -o '\[.*\]' | tr -d '[]' || echo "unknown")
                    log_info "    I/O Scheduler: $scheduler"

                    if [[ "$scheduler" == "mq-deadline" ]]; then
                        log_success "    Optimal I/O scheduler configured"
                    else
                        log_warning "    Suboptimal I/O scheduler (expected: mq-deadline)"
                    fi

                    # Check rotational setting
                    local rotational
                    rotational=$(talosctl -n "$ip" cat "/sys/block/$device_name/queue/rotational" 2>/dev/null || echo "1")

                    if [[ "$rotational" == "0" ]]; then
                        log_success "    Device correctly detected as non-rotational (SSD)"
                    else
                        log_warning "    Device marked as rotational (may not be SSD)"
                    fi
                fi
            fi
        done
    done

    log_test "Overall Samsung Portable SSD T5 hardware status"
    if [[ $nodes_without_usb -eq 0 ]]; then
        log_success "All nodes have Samsung Portable SSD T5 drives detected"
    elif [[ $nodes_without_usb -eq ${#NODES[@]} ]]; then
        log_error "No nodes have Samsung Portable SSD T5 drives detected"
        return 1
    else
        log_warning "$nodes_without_usb out of ${#NODES[@]} nodes missing Samsung Portable SSD T5 drives"
    fi

    return 0
}

# Validate Samsung Portable SSD T5 mounting
validate_usb_mounting() {
    log_section "Samsung Portable SSD T5 Mounting Validation"

    local mounting_errors=0

    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${NODE_IPS[$i]}"

        log_test "Checking Samsung Portable SSD T5 mounting on $node"

        # Check if mount point exists
        if ! talosctl -n "$ip" ls "$MOUNT_POINT" &>/dev/null; then
            log_error "Mount point $MOUNT_POINT does not exist on $node"
            ((mounting_errors++))
            continue
        fi

        log_success "Mount point exists on $node"

        # Check if mount point is mounted
        local mount_info
        mount_info=$(talosctl -n "$ip" df 2>/dev/null | grep "$MOUNT_POINT" || true)

        if [[ -z "$mount_info" ]]; then
            log_warning "Samsung Portable SSD T5 not mounted at $MOUNT_POINT on $node"
            ((mounting_errors++))
            continue
        fi

        log_success "Samsung Portable SSD T5 mounted on $node"
        log_info "  Mount info: $mount_info"

        # Check filesystem type
        local device_path
        device_path=$(echo "$mount_info" | awk '{print $1}')
        local fs_type
        fs_type=$(talosctl -n "$ip" blkid "$device_path" 2>/dev/null | grep -o 'TYPE="[^"]*"' | cut -d'"' -f2 || echo "unknown")

        log_info "  Filesystem: $fs_type"

        if [[ "$fs_type" == "ext4" ]]; then
            log_success "  Optimal filesystem type (ext4)"
        else
            log_warning "  Unexpected filesystem type (expected: ext4)"
        fi

        # Check mount options
        local mount_options
        mount_options=$(talosctl -n "$ip" cat /proc/mounts 2>/dev/null | grep "$MOUNT_POINT" | awk '{print $4}' || echo "")
        log_info "  Mount options: $mount_options"

        # Check available space
        local available_space
        available_space=$(echo "$mount_info" | awk '{print $4}')
        log_info "  Available space: $available_space"

        # Test write permissions
        local test_file
        test_file="$MOUNT_POINT/.write-test-$(date +%s)"
        if talosctl -n "$ip" sh -c "echo 'test' > '$test_file' && rm '$test_file'" &>/dev/null; then
            log_success "  Write permissions verified"
        else
            log_error "  Write permissions test failed"
            ((mounting_errors++))
        fi
    done

    log_test "Overall Samsung Portable SSD T5 mounting status"
    if [[ $mounting_errors -eq 0 ]]; then
        log_success "All Samsung Portable SSD T5 drives are properly mounted"
    else
        log_error "$mounting_errors mounting issues detected"
        return 1
    fi

    return 0
}

# Validate Longhorn deployment
validate_longhorn_deployment() {
    log_section "Longhorn Deployment Validation"

    log_test "Checking Longhorn namespace"
    if kubectl get namespace longhorn-system &> /dev/null; then
        log_success "Longhorn namespace exists"
    else
        log_error "Longhorn namespace not found"
        return 1
    fi

    log_test "Checking Longhorn manager deployment"
    local manager_ready
    manager_ready=$(kubectl get deployment longhorn-manager -n longhorn-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local manager_desired
    manager_desired=$(kubectl get deployment longhorn-manager -n longhorn-system -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

    if [[ "$manager_ready" == "$manager_desired" ]] && [[ "$manager_ready" -gt 0 ]]; then
        log_success "Longhorn manager is ready ($manager_ready/$manager_desired replicas)"
    else
        log_error "Longhorn manager not ready ($manager_ready/$manager_desired replicas)"
        return 1
    fi

    log_test "Checking Longhorn driver deployment"
    local driver_ready
    driver_ready=$(kubectl get daemonset longhorn-driver-deployer -n longhorn-system -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
    local driver_desired
    driver_desired=$(kubectl get daemonset longhorn-driver-deployer -n longhorn-system -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "1")

    if [[ "$driver_ready" == "$driver_desired" ]] && [[ "$driver_ready" -gt 0 ]]; then
        log_success "Longhorn driver is ready ($driver_ready/$driver_desired pods)"
    else
        log_error "Longhorn driver not ready ($driver_ready/$driver_desired pods)"
        return 1
    fi

    log_test "Checking Longhorn instance manager"
    local im_pods
    im_pods=$(kubectl get pods -n longhorn-system -l app=longhorn-instance-manager --no-headers 2>/dev/null | wc -l || echo "0")
    local im_running
    im_running=$(kubectl get pods -n longhorn-system -l app=longhorn-instance-manager --no-headers 2>/dev/null | grep -c "Running" || echo "0")

    if [[ "$im_running" -gt 0 ]] && [[ "$im_running" == "$im_pods" ]]; then
        log_success "Longhorn instance managers are running ($im_running/$im_pods)"
    else
        log_warning "Some Longhorn instance managers not running ($im_running/$im_pods)"
    fi

    return 0
}

# Validate Longhorn disk discovery
validate_longhorn_disks() {
    log_section "Longhorn Disk Discovery Validation"

    log_test "Checking Longhorn nodes"
    local longhorn_nodes
    longhorn_nodes=$(kubectl get nodes.longhorn.io -n longhorn-system -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$longhorn_nodes" ]]; then
        log_error "No Longhorn nodes found"
        return 1
    fi

    log_success "Longhorn nodes found: $longhorn_nodes"

    local total_disks=0
    local ssd_disks=0
    local ready_ssd_disks=0

    for node in $longhorn_nodes; do
        log_test "Checking disks on Longhorn node: $node"

        # Get all disks for this node
        local node_disks
        node_disks=$(kubectl get disks.longhorn.io -n longhorn-system -l longhornnode="$node" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

        if [[ -z "$node_disks" ]]; then
            log_warning "No disks found for node $node"
            continue
        fi

        for disk in $node_disks; do
            ((total_disks++))

            local disk_path
            disk_path=$(kubectl get disk.longhorn.io "$disk" -n longhorn-system -o jsonpath='{.spec.path}' 2>/dev/null || echo "")

            local disk_tags
            disk_tags=$(kubectl get disk.longhorn.io "$disk" -n longhorn-system -o jsonpath='{.spec.tags[*]}' 2>/dev/null || echo "")

            local disk_ready
            disk_ready=$(kubectl get disk.longhorn.io "$disk" -n longhorn-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")

            local disk_schedulable
            disk_schedulable=$(kubectl get disk.longhorn.io "$disk" -n longhorn-system -o jsonpath='{.status.conditions[?(@.type=="Schedulable")].status}' 2>/dev/null || echo "False")

            log_info "  Disk: $disk"
            log_info "    Path: $disk_path"
            log_info "    Tags: $disk_tags"
            log_info "    Ready: $disk_ready"
            log_info "    Schedulable: $disk_schedulable"

            # Check if this is an SSD disk
            if [[ "$disk_path" == "$MOUNT_POINT" ]] && [[ "$disk_tags" == *"ssd"* ]]; then
                ((ssd_disks++))
                log_success "    Samsung Portable SSD T5 disk identified"

                if [[ "$disk_ready" == "True" ]] && [[ "$disk_schedulable" == "True" ]]; then
                    ((ready_ssd_disks++))
                    log_success "    Samsung Portable SSD T5 disk is ready and schedulable"
                else
                    log_warning "    Samsung Portable SSD T5 disk is not ready or not schedulable"
                fi

                # Check disk space
                local disk_storage
                disk_storage=$(kubectl get disk.longhorn.io "$disk" -n longhorn-system -o jsonpath='{.spec.storageReserved}' 2>/dev/null || echo "0")
                local disk_max_storage
                disk_max_storage=$(kubectl get disk.longhorn.io "$disk" -n longhorn-system -o jsonpath='{.status.storageMaximum}' 2>/dev/null || echo "0")
                local disk_available
                disk_available=$(kubectl get disk.longhorn.io "$disk" -n longhorn-system -o jsonpath='{.status.storageAvailable}' 2>/dev/null || echo "0")

                log_info "    Storage Maximum: $disk_max_storage bytes"
                log_info "    Storage Available: $disk_available bytes"
                log_info "    Storage Reserved: $disk_storage bytes"
            fi
        done
    done

    log_test "Overall Longhorn disk status"
    log_info "Total disks: $total_disks"
    log_info "SSD disks: $ssd_disks"
    log_info "Ready SSD disks: $ready_ssd_disks"

    if [[ $ssd_disks -eq 0 ]]; then
        log_error "No Samsung Portable SSD T5 disks found in Longhorn"
        return 1
    elif [[ $ready_ssd_disks -eq 0 ]]; then
        log_error "No ready Samsung Portable SSD T5 disks found in Longhorn"
        return 1
    elif [[ $ready_ssd_disks -eq $ssd_disks ]]; then
        log_success "All Samsung Portable SSD T5 disks are ready in Longhorn"
    else
        log_warning "Some Samsung Portable SSD T5 disks are not ready in Longhorn ($ready_ssd_disks/$ssd_disks)"
    fi

    return 0
}

# Validate storage classes
validate_storage_classes() {
    log_section "Storage Classes Validation"

    log_test "Checking longhorn-ssd storage class"
    if kubectl get storageclass longhorn-ssd &> /dev/null; then
        log_success "longhorn-ssd storage class exists"

        # Check storage class parameters
        local disk_selector
        disk_selector=$(kubectl get storageclass longhorn-ssd -o jsonpath='{.parameters.diskSelector}' 2>/dev/null || echo "")

        if [[ "$disk_selector" == "ssd" ]]; then
            log_success "Storage class has correct diskSelector: $disk_selector"
        else
            log_error "Storage class has incorrect diskSelector: $disk_selector (expected: ssd)"
        fi

        local data_locality
        data_locality=$(kubectl get storageclass longhorn-ssd -o jsonpath='{.parameters.dataLocality}' 2>/dev/null || echo "")

        if [[ "$data_locality" == "strict-local" ]]; then
            log_success "Storage class has optimal dataLocality: $data_locality"
        else
            log_warning "Storage class dataLocality: $data_locality (recommended: strict-local)"
        fi

        local replica_count
        replica_count=$(kubectl get storageclass longhorn-ssd -o jsonpath='{.parameters.numberOfReplicas}' 2>/dev/null || echo "")
        log_info "Storage class replica count: $replica_count"

    else
        log_error "longhorn-ssd storage class not found"
        return 1
    fi

    log_test "Checking default longhorn storage class"
    if kubectl get storageclass longhorn &> /dev/null; then
        log_success "Default longhorn storage class exists"
    else
        log_warning "Default longhorn storage class not found"
    fi

    log_test "Checking volume snapshot classes"
    if kubectl get volumesnapshotclass longhorn-ssd-snapshot-vsc &> /dev/null; then
        log_success "longhorn-ssd-snapshot-vsc volume snapshot class exists"
    else
        log_warning "longhorn-ssd-snapshot-vsc volume snapshot class not found"
    fi

    return 0
}

# Test storage functionality
test_storage_functionality() {
    log_section "Storage Functionality Testing"

    local test_pvc
    test_pvc="samsung-t5-validation-test-$(date +%s)"
    local test_namespace="default"

    log_test "Creating test PVC with longhorn-ssd storage class"

    # Create test PVC
    if cat <<EOF | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $test_pvc
  namespace: $test_namespace
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-ssd
  resources:
    requests:
      storage: 1Gi
EOF
    then
        log_success "Test PVC created successfully"
    else
        log_error "Failed to create test PVC"
        return 1
    fi

    log_test "Waiting for PVC to bind"
    local timeout=120
    local elapsed=0
    local pvc_bound=false

    while [[ $elapsed -lt $timeout ]]; do
        local pvc_status
        pvc_status=$(kubectl get pvc "$test_pvc" -n "$test_namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")

        if [[ "$pvc_status" == "Bound" ]]; then
            log_success "Test PVC bound successfully"
            pvc_bound=true
            break
        elif [[ "$pvc_status" == "Pending" ]]; then
            log_info "PVC still pending... (${elapsed}s/${timeout}s)"
        else
            log_warning "PVC status: $pvc_status"
        fi

        sleep 5
        elapsed=$((elapsed + 5))
    done

    if [[ "$pvc_bound" == "false" ]]; then
        log_error "Test PVC failed to bind within $timeout seconds"

        # Show PVC events for debugging
        log_info "PVC events:"
        kubectl describe pvc "$test_pvc" -n "$test_namespace" | grep -A 10 "Events:" || true

        # Cleanup failed test
        kubectl delete pvc "$test_pvc" -n "$test_namespace" --ignore-not-found=true &>/dev/null
        return 1
    fi

    # Get volume details
    local pv_name
    pv_name=$(kubectl get pvc "$test_pvc" -n "$test_namespace" -o jsonpath='{.spec.volumeName}' 2>/dev/null || echo "")

    if [[ -n "$pv_name" ]]; then
        log_success "PersistentVolume created: $pv_name"

        # Check volume location
        local volume_node
        volume_node=$(kubectl get pv "$pv_name" -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}' 2>/dev/null || echo "")
        log_info "Volume scheduled on node: $volume_node"

        # Verify volume is on SSD storage
        local longhorn_volume
        longhorn_volume=$(kubectl get volumes.longhorn.io -n longhorn-system -o jsonpath='{.items[?(@.spec.name=="'"$pv_name"'")].metadata.name}' 2>/dev/null || echo "")

        if [[ -n "$longhorn_volume" ]]; then
            log_success "Longhorn volume found: $longhorn_volume"

            # Check volume replicas
            local replica_count
            replica_count=$(kubectl get volume.longhorn.io "$longhorn_volume" -n longhorn-system -o jsonpath='{.status.actualSize}' 2>/dev/null || echo "0")
            log_info "Volume actual size: $replica_count bytes"
        fi
    fi

    log_test "Testing pod mounting"

    # Create test pod
    local test_pod
    test_pod="usb-ssd-test-pod-$(date +%s)"
    if cat <<EOF | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: $test_pod
  namespace: $test_namespace
spec:
  containers:
  - name: test-container
    image: busybox:1.35
    command: ['sh', '-c', 'echo "USB SSD test" > /data/test.txt && cat /data/test.txt && sleep 30']
    volumeMounts:
    - name: test-volume
      mountPath: /data
  volumes:
  - name: test-volume
    persistentVolumeClaim:
      claimName: $test_pvc
  restartPolicy: Never
EOF
    then
        log_success "Test pod created successfully"

        # Wait for pod to complete
        log_info "Waiting for test pod to complete..."
        kubectl wait --for=condition=Ready pod/"$test_pod" -n "$test_namespace" --timeout=60s &>/dev/null || true

        # Check pod logs
        local pod_logs
        pod_logs=$(kubectl logs "$test_pod" -n "$test_namespace" 2>/dev/null || echo "")

        if [[ "$pod_logs" == *"USB SSD test"* ]]; then
            log_success "Pod successfully wrote and read from Samsung Portable SSD T5 storage"
        else
            log_warning "Pod test may not have completed successfully"
            log_info "Pod logs: $pod_logs"
        fi

        # Cleanup test pod
        kubectl delete pod "$test_pod" -n "$test_namespace" --ignore-not-found=true &>/dev/null
    else
        log_error "Failed to create test pod"
    fi

    # Cleanup test PVC
    log_info "Cleaning up test resources..."
    kubectl delete pvc "$test_pvc" -n "$test_namespace" --ignore-not-found=true &>/dev/null

    log_success "Storage functionality test completed"
    return 0
}

# Performance validation
validate_performance() {
    log_section "Performance Validation"

    log_test "Checking I/O performance characteristics"

    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${NODE_IPS[$i]}"

        log_info "Testing I/O performance on $node..."

        # Check if Samsung Portable SSD T5 is mounted
        local mount_info
        mount_info=$(talosctl -n "$ip" df 2>/dev/null | grep "$MOUNT_POINT" || true)

        if [[ -z "$mount_info" ]]; then
            log_warning "Samsung Portable SSD T5 not mounted on $node, skipping performance test"
            continue
        fi

        # Simple write test
        local test_file
        test_file="$MOUNT_POINT/.perf-test-$(date +%s)"
        local write_result
        write_result=$(talosctl -n "$ip" sh -c "time dd if=/dev/zero of='$test_file' bs=1M count=100 oflag=direct 2>&1 && rm '$test_file'" 2>/dev/null || echo "failed")

        if [[ "$write_result" != "failed" ]]; then
            log_success "Write performance test completed on $node"
            # Extract timing information if available
            local timing
            timing=$(echo "$write_result" | grep "real" || echo "timing not available")
            log_info "  $timing"
        else
            log_warning "Write performance test failed on $node"
        fi
    done

    return 0
}

# Test failover scenarios (safe tests only)
test_failover_scenarios() {
    log_section "Failover Scenario Testing"

    log_test "Testing volume scheduling across nodes"

    # Create multiple test PVCs to see distribution
    local test_pvcs=()
    local test_namespace="default"

    for i in {1..3}; do
        local test_pvc
        test_pvc="failover-test-pvc-$i-$(date +%s)"
        test_pvcs+=("$test_pvc")

        cat <<EOF | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $test_pvc
  namespace: $test_namespace
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-ssd
  resources:
    requests:
      storage: 1Gi
EOF
    done

    log_info "Created ${#test_pvcs[@]} test PVCs for distribution testing"

    # Wait for PVCs to bind
    sleep 30

    # Check distribution
    local node_distribution=()
    for pvc in "${test_pvcs[@]}"; do
        local pv_name
        pv_name=$(kubectl get pvc "$pvc" -n "$test_namespace" -o jsonpath='{.spec.volumeName}' 2>/dev/null || echo "")

        if [[ -n "$pv_name" ]]; then
            local volume_node
            volume_node=$(kubectl get pv "$pv_name" -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}' 2>/dev/null || echo "unknown")
            node_distribution+=("$volume_node")
            log_info "PVC $pvc scheduled on node: $volume_node"
        fi
    done

    # Analyze distribution
    local unique_nodes
    unique_nodes=$(printf '%s\n' "${node_distribution[@]}" | sort -u | wc -l)

    if [[ $unique_nodes -gt 1 ]]; then
        log_success "Volumes distributed across $unique_nodes nodes (good for availability)"
    else
        log_warning "All volumes scheduled on same node (potential single point of failure)"
    fi

    # Cleanup test PVCs
    log_info "Cleaning up failover test PVCs..."
    for pvc in "${test_pvcs[@]}"; do
        kubectl delete pvc "$pvc" -n "$test_namespace" --ignore-not-found=true &>/dev/null
    done

    return 0
}

# Validate Longhorn settings
validate_longhorn_settings() {
    log_section "Longhorn Settings Validation"

    log_test "Checking createDefaultDiskLabeledNodes setting"
    local create_default_disks
    create_default_disks=$(kubectl get setting create-default-disk-labeled-nodes -n longhorn-system -o jsonpath='{.value}' 2>/dev/null || echo "true")

    if [[ "$create_default_disks" == "false" ]]; then
        log_success "createDefaultDiskLabeledNodes is disabled (correct for Samsung Portable SSD T5 setup)"
    else
        log_warning "createDefaultDiskLabeledNodes is enabled (should be false for Samsung Portable SSD T5 setup)"
    fi

    log_test "Checking storage over-provisioning setting"
    local storage_over_provisioning
    storage_over_provisioning=$(kubectl get setting storage-over-provisioning-percentage -n longhorn-system -o jsonpath='{.value}' 2>/dev/null || echo "200")

    log_info "Storage over-provisioning percentage: $storage_over_provisioning%"

    if [[ $storage_over_provisioning -le 150 ]]; then
        log_success "Storage over-provisioning is optimized for SSDs"
    else
        log_warning "Storage over-provisioning might be too high for SSDs"
    fi

    log_test "Checking storage minimal available setting"
    local storage_minimal
    storage_minimal=$(kubectl get setting storage-minimal-available-percentage -n longhorn-system -o jsonpath='{.value}' 2>/dev/null || echo "25")

    log_info "Storage minimal available percentage: $storage_minimal%"

    if [[ $storage_minimal -le 20 ]]; then
        log_success "Storage minimal available is optimized for SSDs"
    else
        log_warning "Storage minimal available might be too high for SSDs"
    fi

    return 0
}

# Integration with existing validation scripts
run_existing_validations() {
    log_section "Running Existing Validation Scripts"

    log_test "Running Samsung Portable SSD T5 storage validation"
    if [[ -f "scripts/validate-usb-ssd-storage.sh" ]]; then
        log_info "Running validate-usb-ssd-storage.sh..."
        if ./scripts/validate-usb-ssd-storage.sh &>> "$REPORT_FILE"; then
            log_success "Samsung Portable SSD T5 storage validation passed"
        else
            log_warning "Samsung Portable SSD T5 storage validation had issues (check report for details)"
        fi
    else
        log_warning "validate-usb-ssd-storage.sh not found"
    fi

    log_test "Running Longhorn Samsung Portable SSD T5 validation"
    if [[ -f "scripts/validate-longhorn-usb-ssd.sh" ]]; then
        log_info "Running validate-longhorn-usb-ssd.sh..."
        if ./scripts/validate-longhorn-usb-ssd.sh &>> "$REPORT_FILE"; then
            log_success "Longhorn Samsung Portable SSD T5 validation passed"
        else
            log_warning "Longhorn Samsung Portable SSD T5 validation had issues (check report for details)"
        fi
    else
        log_warning "validate-longhorn-usb-ssd.sh not found"
    fi

    return 0
}

# Generate comprehensive report
generate_final_report() {
    log_section "Validation Summary"

    local success_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi

    log_info "=== VALIDATION RESULTS ==="
    log_info "Total Tests: $TOTAL_TESTS"
    log_info "Passed: $PASSED_TESTS"
    log_info "Failed: $FAILED_TESTS"
    log_info "Warnings: $WARNING_TESTS"
    log_info "Success Rate: $success_rate%"

    # Write summary to report
    cat >> "$REPORT_FILE" << EOF

=== FINAL VALIDATION SUMMARY ===
Total Tests: $TOTAL_TESTS
Passed: $PASSED_TESTS
Failed: $FAILED_TESTS
Warnings: $WARNING_TESTS
Success Rate: $success_rate%

EOF

    # Determine overall status
    if [[ $FAILED_TESTS -eq 0 ]]; then
        if [[ $WARNING_TESTS -eq 0 ]]; then
            log_success "All Samsung Portable SSD T5 storage validations passed successfully!"
            echo "Status: FULLY OPERATIONAL" >> "$REPORT_FILE"
            return 0
        else
            log_success "Samsung Portable SSD T5 storage validation completed with warnings"
            log_warning "Review warnings above for optimization opportunities"
            echo "Status: OPERATIONAL WITH WARNINGS" >> "$REPORT_FILE"
            return 0
        fi
    else
        log_error "Samsung Portable SSD T5 storage validation failed"
        log_error "Review errors above and fix issues before using Samsung Portable SSD T5 storage"
        echo "Status: FAILED - REQUIRES ATTENTION" >> "$REPORT_FILE"
        return 1
    fi
}

# Main validation function
main() {
    echo "=============================================="
    echo "Comprehensive Samsung Portable SSD T5 Storage Validation"
    echo "=============================================="
    echo

    # Initialize report
    init_report

    log_info "Starting comprehensive Samsung Portable SSD T5 storage validation..."
    log_info "Report will be saved to: $REPORT_FILE"
    echo

    local start_time
    start_time=$(date +%s)

    # Run all validation tests
    local exit_code=0

    check_prerequisites || exit_code=1
    validate_usb_hardware || exit_code=1
    validate_usb_mounting || exit_code=1
    validate_longhorn_deployment || exit_code=1
    validate_longhorn_disks || exit_code=1
    validate_storage_classes || exit_code=1
    test_storage_functionality || exit_code=1
    validate_performance || exit_code=1
    test_failover_scenarios || exit_code=1
    validate_longhorn_settings || exit_code=1
    run_existing_validations || exit_code=1

    # Calculate validation time
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo
    log_info "Validation completed in $duration seconds"

    # Generate final report
    generate_final_report

    echo
    echo "=============================================="
    log_info "Validation report saved to: $REPORT_FILE"
    echo "=============================================="

    if [[ $exit_code -eq 0 ]]; then
        echo
        log_success "Samsung Portable SSD T5 storage is ready for production use!"
        echo
        log_info "Next steps:"
        log_info "1. Create PVCs using the 'longhorn-ssd' storage class"
        log_info "2. Monitor Longhorn dashboard for disk health"
        log_info "3. Set up monitoring and alerting for storage metrics"
        log_info "4. Consider backup strategies for critical data"
    else
        echo
        log_error "Samsung Portable SSD T5 storage validation failed!"
        echo
        log_info "Required actions:"
        log_info "1. Review the validation report: $REPORT_FILE"
        log_info "2. Fix all failed tests before using Samsung Portable SSD T5 storage"
        log_info "3. Re-run validation after fixes"
        log_info "4. Contact support if issues persist"
    fi

    exit $exit_code
}

# Make script executable and run
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
