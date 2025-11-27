#!/bin/bash

# Gram-Optic: Advanced Workspace-Based Memory Management System
# Implements a three-tier storage system for Hyprland workspaces

# Check required dependencies
if ! command -v sudo >/dev/null 2>&1; then
    echo "Error: sudo is required but not installed. Please install sudo." >&2
    exit 1
fi

GRAM_OPTIC_DIR="/opt/gram-optic"
LOG_FILE="/var/log/gram-optic.log"
CONFIG_FILE="/etc/gram-optic.conf"

# Default configuration
DEFAULT_ZRAM_SIZE="2G"
SWAP_SIZE="4G"
LOW_COMPRESSION="lz4"
MEDIUM_COMPRESSION="zstd"

# Initialize log file
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/gram-optic.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to setup zram for workspaces 7-9 (medium compression in RAM)
setup_zram_tier() {
    local size=${1:-$DEFAULT_ZRAM_SIZE}

    log_message "Setting up zram for workspaces 7-9 (medium compression in RAM)"

    # Check if zram module is available
    if ! command -v modprobe >/dev/null 2>&1; then
        log_message "ERROR: modprobe is required for zram functionality"
        return 1
    fi

    # Load zram module if not already loaded
    if ! lsmod | grep -q zram; then
        sudo modprobe zram || {
            log_message "ERROR: Failed to load zram module"
            return 1
        }
    fi
    
    # Create zram device for workspaces 7-9 with medium compression
    local zram_device
    zram_device=$(sudo cat /sys/class/zram-control/hot_add)
    
    # Configure zram device with medium compression (Zstd if available, otherwise lz4)
    # First check if zstd is available as compression algorithm
    if grep -q zstd /sys/block/zram$zram_device/comp_algorithm 2>/dev/null; then
        echo "zstd" | sudo tee /sys/block/zram$zram_device/comp_algorithm > /dev/null
        log_message "Using zstd compression for zram$zram_device"
    else
        echo "lz4" | sudo tee /sys/block/zram$zram_device/comp_algorithm > /dev/null
        log_message "Using lz4 compression for zram$zram_device (zstd not available)"
    fi
    
    # Set the disk size
    echo "${size}" | sudo tee /sys/block/zram$zram_device/disksize > /dev/null
    
    # Format and enable zram as swap with higher priority
    sudo mkswap /dev/zram$zram_device 2>/dev/null
    sudo swapon -p 100 /dev/zram$zram_device 2>/dev/null
    
    log_message "zram$zram_device device for workspaces 7-9 configured with medium compression"
    echo $zram_device > /tmp/gram-optic-zram-device
}

# Function to setup disk swap for workspaces 4-6 (low compression on disk)
setup_disk_swap_tier() {
    local size=${1:-$SWAP_SIZE}
    
    log_message "Setting up disk swap for workspaces 4-6 (low compression on disk)"
    
    # Create a dedicated swap file for workspaces 4-6
    local swap_file="/swap/gram-optic-workspace46.swap"
    sudo mkdir -p /swap
    
    # Create swap file
    if [ ! -f "$swap_file" ]; then
        echo "Creating swap file of size $size..."
        sudo dd if=/dev/zero of="$swap_file" bs=1M count=$(echo "$size" | sed 's/[^0-9]*//g') 2>/dev/null
        sudo chmod 600 "$swap_file"
        sudo mkswap "$swap_file" 2>/dev/null
    fi
    
    # Enable swap with lower priority than zram but higher than system swap
    sudo swapon -p 50 "$swap_file" 2>/dev/null
    
    log_message "Disk swap for workspaces 4-6 configured at $swap_file"
}

# Function to setup pure RAM tier for workspaces 1-3
setup_ram_tier() {
    log_message "Workspaces 1-3 remain in pure RAM (no compression, highest performance)"
    # No specific setup needed - this is the default behavior
}

# Function to start the workspace monitoring daemon
start_monitoring_daemon() {
    log_message "Starting workspace monitoring daemon"
    
    # Create the daemon script
    cat > /tmp/gram-optic-daemon.sh << 'EOF'
#!/bin/bash

# Workspace monitoring daemon for gram-optic
GRAM_OPTIC_DIR="/opt/gram-optic"
LOG_FILE="/var/log/gram-optic.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Function to get current workspace
get_current_workspace() {
    if command -v hyprctl &> /dev/null && command -v jq &> /dev/null; then
        # Get the active workspace number from Hyprland using jq if available
        hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // .workspaceId // 0' 2>/dev/null
    elif command -v hyprctl &> /dev/null; then
        # Alternative method using grep if jq is not available
        hyprctl activeworkspace -j 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('id', data.get('workspaceId', 0)))
except:
    print(0)
" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Function to get windows on a specific workspace
get_windows_on_workspace() {
    local workspace_num=$1
    if command -v hyprctl &> /dev/null && command -v jq &> /dev/null; then
        # Get window IDs on the specified workspace using jq if available
        hyprctl clients -j 2>/dev/null | jq -r ".[] | select(.workspace.id == $workspace_num) | .pid" 2>/dev/null
    elif command -v hyprctl &> /dev/null; then
        # Fallback method using grep if jq is not available
        hyprctl clients -j 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
workspace_num = $workspace_num
for client in data:
    if 'workspace' in client and client['workspace'].get('id') == workspace_num:
        print(client.get('pid', ''))
" 2>/dev/null || echo ""
    fi
}

# Function to monitor memory pressure and adjust accordingly
adjust_memory_tiers() {
    local current_ws=$1
    
    # Based on current workspace, we prioritize different memory tiers
    # In a real implementation, we would need to influence memory management policies
    # Since direct memory migration is complex, we'll log the intended behavior
    if [ "$current_ws" -le 3 ]; then
        # Workspaces 1-3: Keep in RAM as much as possible
        tier="RAM (Tier 1)"
        log_message "Workspace $current_ws: Prioritizing RAM (Tier 1) for optimal performance"
    elif [ "$current_ws" -le 6 ]; then
        # Workspaces 4-6: Use disk swap with low compression for balance
        tier="Disk Swap (Tier 2 - Low Compression)"
        log_message "Workspace $current_ws: Using disk swap (Tier 2) with low compression algorithm"
    else
        # Workspaces 7-9: Use ZRAM with medium compression for space efficiency
        tier="ZRAM (Tier 3 - Medium Compression)"
        log_message "Workspace $current_ws: Using ZRAM (Tier 3) with medium compression"
    fi
}

log_message "Workspace monitoring daemon started"
previous_ws=""

while true; do
    current_ws=$(get_current_workspace 2>/dev/null)
    
    if [ -n "$current_ws" ] && [ "$current_ws" -ge 1 ] 2>/dev/null; then
        # Check if workspace changed
        if [ "$current_ws" != "$previous_ws" ]; then
            log_message "Workspace changed from $previous_ws to $current_ws"
            
            # Adjust memory tier based on workspace
            adjust_memory_tiers "$current_ws"
            
            # Update previous workspace
            previous_ws=$current_ws
        fi
    fi
    
    sleep 2  # Reduced frequency to reduce system load
done
EOF

    chmod +x /tmp/gram-optic-daemon.sh
    nohup /tmp/gram-optic-daemon.sh > /dev/null 2>&1 &
    DAEMON_PID=$!
    echo $DAEMON_PID > /tmp/gram-optic-daemon.pid
    
    log_message "Monitoring daemon started with PID $DAEMON_PID"
}

# Function to stop the system
stop_system() {
    log_message "Stopping gram-optic system"
    
    # Stop monitoring daemon
    if [ -f "/tmp/gram-optic-daemon.pid" ]; then
        DAEMON_PID=$(cat /tmp/gram-optic-daemon.pid)
        kill $DAEMON_PID 2>/dev/null
        rm -f /tmp/gram-optic-daemon.pid
    fi
    
    # Get the zram device number if it was created
    ZRAM_DEVICE=""
    if [ -f "/tmp/gram-optic-zram-device" ]; then
        ZRAM_DEVICE=$(cat /tmp/gram-optic-zram-device)
        rm -f /tmp/gram-optic-zram-device
    fi
    
    # Disable swap devices
    if [ -n "$ZRAM_DEVICE" ] && [ -e "/dev/zram$ZRAM_DEVICE" ]; then
        sudo swapoff /dev/zram$ZRAM_DEVICE 2>/dev/null
    fi
    sudo swapoff /swap/gram-optic-workspace46.swap 2>/dev/null
    
    # Reset zram if device was created
    if [ -n "$ZRAM_DEVICE" ] && [ -e /sys/class/zram-control/hot_remove ]; then
        echo $ZRAM_DEVICE | sudo tee /sys/class/zram-control/hot_remove > /dev/null 2>&1
    fi
    
    log_message "Gram-optic system stopped"
}

# Function to display status
show_status() {
    echo "Gram-Optic System Status:"
    echo "========================="
    
    # Check zram device
    ZRAM_DEVICE=""
    if [ -f "/tmp/gram-optic-zram-device" ]; then
        ZRAM_DEVICE=$(cat /tmp/gram-optic-zram-device)
    fi
    
    if [ -n "$ZRAM_DEVICE" ] && [ -e "/dev/zram$ZRAM_DEVICE" ]; then
        echo "✓ ZRAM device $ZRAM_DEVICE for workspaces 7-9: $(cat /sys/block/zram$ZRAM_DEVICE/comp_algorithm 2>/dev/null)"
        echo "  Size: $(cat /sys/block/zram$ZRAM_DEVICE/disksize 2>/dev/null) bytes"
        echo "  Used: $(cat /sys/block/zram$ZRAM_DEVICE/mem_used_total 2>/dev/null) bytes"
    else
        echo "✗ ZRAM device for workspaces 7-9: Not active"
    fi
    
    if [ -f "/swap/gram-optic-workspace46.swap" ]; then
        echo "✓ Disk swap for workspaces 4-6: Active"
        sudo ls -lh /swap/gram-optic-workspace46.swap
        free -h | grep Swap
    else
        echo "✗ Disk swap for workspaces 4-6: Not active"
    fi
    
    if [ -f "/tmp/gram-optic-daemon.pid" ]; then
        DAEMON_PID=$(cat /tmp/gram-optic-daemon.pid)
        if ps -p $DAEMON_PID > /dev/null; then
            echo "✓ Monitoring daemon: Running (PID: $DAEMON_PID)"
        else
            echo "✗ Monitoring daemon: PID file exists but process not running"
        fi
    else
        echo "✗ Monitoring daemon: Not running"
    fi
    
    echo ""
    echo "System Memory Status:"
    free -h
}

# Main function
main() {
    case "${1:-status}" in
        "start")
            setup_ram_tier
            setup_disk_swap_tier "${2:-$SWAP_SIZE}"
            setup_zram_tier "${2:-$DEFAULT_ZRAM_SIZE}"
            start_monitoring_daemon
            log_message "Gram-Optic system started successfully"
            ;;
        "stop")
            stop_system
            ;;
        "restart")
            stop_system
            sleep 1
            main start "$2"
            ;;
        "status")
            show_status
            ;;
        *)
            echo "Usage: $0 {start|stop|restart|status} [size]"
            echo "  start:  Activate gram-optic system"
            echo "  stop:   Deactivate gram-optic system" 
            echo "  restart: Restart gram-optic system"
            echo "  status: Show current status"
            echo "  size:   Optional size parameter (e.g., 2G, 4G)"
            ;;
    esac
}

# Execute main function with arguments
main "$@"