#!/bin/bash
# Unifi UDM Pro BGP Configuration Script for Talos Cluster Integration
# This script configures FRR (Free Range Routing) on the UDM Pro to peer with Cilium BGP

set -euo pipefail

# Configuration variables
CLUSTER_ASN=64512
UNIFI_ASN=64513
CLUSTER_SUBNET="172.29.51.0/24"
CLUSTER_NODES=("172.29.51.11" "172.29.51.12" "172.29.51.13")
CLUSTER_VIP="172.29.51.10"
LOADBALANCER_POOL="172.29.51.100/25"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Check if running on UDM Pro
check_udm_pro() {
    if [[ ! -f /etc/unifi-os/ubnt-bstrap.env ]]; then
        error "This script must be run on a Unifi UDM Pro"
    fi
    log "Confirmed running on UDM Pro"
}

# Install FRR if not already installed
install_frr() {
    log "Checking FRR installation..."

    if ! command -v vtysh &> /dev/null; then
        log "Installing FRR..."
        apt-get update
        apt-get install -y frr frr-pythontools
    else
        log "FRR is already installed"
    fi

    # Enable BGP daemon
    sed -i 's/^bgpd=no$/bgpd=yes/' /etc/frr/daemons

    # Start and enable FRR service
    systemctl enable frr
    systemctl start frr

    log "FRR installation and configuration complete"
}

# Create FRR BGP configuration
create_bgp_config() {
    log "Creating FRR BGP configuration..."

    # Create the FRR configuration file
    cat > /etc/frr/frr.conf << EOF
!
! FRR configuration for Talos Kubernetes Cluster BGP Peering
! Generated on $(date)
!
frr version 8.4.4
frr defaults traditional
hostname udm-pro
log syslog informational
no ipv6 forwarding
service integrated-vtysh-config
!
! BGP Configuration
!
router bgp ${UNIFI_ASN}
 bgp router-id 172.29.51.1
 bgp log-neighbor-changes
 bgp bestpath as-path multipath-relax
 bgp bestpath compare-routerid
 timers bgp 30 90
 !
 ! Cluster node neighbors
EOF

    # Add each cluster node as a BGP neighbor
    for node in "${CLUSTER_NODES[@]}"; do
        cat >> /etc/frr/frr.conf << EOF
 neighbor ${node} remote-as ${CLUSTER_ASN}
 neighbor ${node} description "Talos Node ${node}"
 neighbor ${node} timers 30 90
 neighbor ${node} timers connect 10
 neighbor ${node} capability extended-nexthop
 !
EOF
    done

    cat >> /etc/frr/frr.conf << EOF
 !
 ! Address family IPv4 unicast
 !
 address-family ipv4 unicast
  redistribute connected
  redistribute static
  !
EOF

    # Configure neighbors for IPv4 unicast
    for node in "${CLUSTER_NODES[@]}"; do
        cat >> /etc/frr/frr.conf << EOF
  neighbor ${node} activate
  neighbor ${node} soft-reconfiguration inbound
  neighbor ${node} route-map CLUSTER-IN in
  neighbor ${node} route-map CLUSTER-OUT out
  !
EOF
    done

    cat >> /etc/frr/frr.conf << EOF
 exit-address-family
 !
exit
!
! Route Maps
!
route-map CLUSTER-IN permit 10
 description "Accept routes from Talos cluster"
 set metric 100
 set local-preference 200
exit
!
route-map CLUSTER-OUT permit 10
 description "Advertise local routes to Talos cluster"
 match ip address prefix-list LOCAL-NETWORKS
 set metric 50
exit
!
! Prefix Lists
!
ip prefix-list LOCAL-NETWORKS seq 10 permit ${CLUSTER_SUBNET}
ip prefix-list LOCAL-NETWORKS seq 20 permit 172.29.0.0/16
ip prefix-list LOCAL-NETWORKS seq 30 permit 192.168.0.0/16
!
! Static routes for load balancer pool
!
ip route ${LOADBALANCER_POOL} null0 250
!
! Access Lists
!
access-list 10 permit ${CLUSTER_SUBNET}
access-list 10 permit 172.29.0.0 0.0.255.255
access-list 10 permit 192.168.0.0 0.0.255.255
access-list 10 deny any
!
! Log configuration
!
log file /var/log/frr/frr.log
log facility local4
!
line vty
!
end
EOF

    log "FRR configuration created successfully"
}

# Configure iptables rules for BGP
configure_iptables() {
    log "Configuring iptables rules for BGP..."

    # Allow BGP traffic (port 179)
    iptables -I INPUT -p tcp --dport 179 -j ACCEPT
    iptables -I OUTPUT -p tcp --sport 179 -j ACCEPT

    # Allow traffic from cluster nodes
    for node in "${CLUSTER_NODES[@]}"; do
        iptables -I INPUT -s "${node}" -j ACCEPT
        iptables -I OUTPUT -d "${node}" -j ACCEPT
    done

    # Save iptables rules
    iptables-save > /etc/iptables/rules.v4

    log "iptables rules configured"
}

# Enable IP forwarding
enable_ip_forwarding() {
    log "Enabling IP forwarding..."

    echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
    echo 'net.ipv4.conf.all.forwarding = 1' >> /etc/sysctl.conf
    sysctl -p

    log "IP forwarding enabled"
}

# Create monitoring script
create_monitoring_script() {
    log "Creating BGP monitoring script..."

    cat > /usr/local/bin/bgp-monitor.sh << 'EOF'
#!/bin/bash
# BGP Monitoring Script for Talos Cluster Integration

LOG_FILE="/var/log/bgp-monitor.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$DATE] Starting BGP monitoring check" >> $LOG_FILE

# Check if FRR is running
if ! systemctl is-active --quiet frr; then
    echo "[$DATE] ERROR: FRR service is not running" >> $LOG_FILE
    systemctl start frr
    exit 1
fi

# Check BGP neighbors
NEIGHBORS=$(vtysh -c "show bgp neighbors" 2>/dev/null | grep -E "BGP neighbor is|BGP state" | paste - -)

if [[ -z "$NEIGHBORS" ]]; then
    echo "[$DATE] ERROR: No BGP neighbors found" >> $LOG_FILE
    exit 1
fi

echo "[$DATE] BGP Status:" >> $LOG_FILE
echo "$NEIGHBORS" >> $LOG_FILE

# Check for established connections
ESTABLISHED=$(vtysh -c "show bgp summary" 2>/dev/null | grep -c "Established")
echo "[$DATE] Established BGP sessions: $ESTABLISHED" >> $LOG_FILE

# Check routes
ROUTES=$(vtysh -c "show ip route bgp" 2>/dev/null | wc -l)
echo "[$DATE] BGP routes: $ROUTES" >> $LOG_FILE

echo "[$DATE] BGP monitoring check complete" >> $LOG_FILE
EOF

    chmod +x /usr/local/bin/bgp-monitor.sh

    # Create cron job for monitoring
    echo "*/5 * * * * /usr/local/bin/bgp-monitor.sh" | crontab -

    log "BGP monitoring script created and scheduled"
}

# Create backup and restore functions
create_backup_restore() {
    log "Creating backup and restore functions..."

    cat > /usr/local/bin/bgp-backup.sh << 'EOF'
#!/bin/bash
# BGP Configuration Backup Script

BACKUP_DIR="/opt/bgp-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/frr_config_$TIMESTAMP.tar.gz"

mkdir -p $BACKUP_DIR

# Create backup
tar -czf $BACKUP_FILE /etc/frr/frr.conf /etc/frr/daemons

# Keep only last 10 backups
find $BACKUP_DIR -name "frr_config_*.tar.gz" -type f -mtime +10 -delete

echo "Backup created: $BACKUP_FILE"
EOF

    chmod +x /usr/local/bin/bgp-backup.sh

    # Schedule daily backup
    echo "0 2 * * * /usr/local/bin/bgp-backup.sh" | crontab -u root -

    log "Backup script created and scheduled"
}

# Main execution
main() {
    log "Starting Unifi BGP configuration for Talos cluster..."

    check_udm_pro
    install_frr
    create_bgp_config
    configure_iptables
    enable_ip_forwarding
    create_monitoring_script
    create_backup_restore

    # Restart FRR to apply configuration
    log "Restarting FRR service..."
    systemctl restart frr

    # Wait for FRR to start
    sleep 5

    # Display BGP status
    log "BGP Configuration Summary:"
    echo "==========================================="
    echo "Local ASN: $UNIFI_ASN"
    echo "Cluster ASN: $CLUSTER_ASN"
    echo "Cluster Nodes: ${CLUSTER_NODES[*]}"
    echo "Load Balancer Pool: $LOADBALANCER_POOL"
    echo "==========================================="

    log "Checking BGP neighbor status..."
    vtysh -c "show bgp summary" || warn "BGP neighbors not yet established (this is normal on first run)"

    log "BGP configuration complete!"
    log "Monitor BGP status with: vtysh -c 'show bgp summary'"
    log "View BGP routes with: vtysh -c 'show ip route bgp'"
    log "Check logs with: tail -f /var/log/frr/frr.log"
}

# Run main function
main "$@"
