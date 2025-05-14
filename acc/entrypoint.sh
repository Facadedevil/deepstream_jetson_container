#!/bin/bash
# Enhanced entrypoint script for Advantech Jetson AI container
# This script dynamically detects hardware and manages resources

# Terminal colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Enable bash error handling
set -e

# Memory management settings (can be overridden by environment variables)
ENABLE_DYNAMIC_MEMORY=${ENABLE_DYNAMIC_MEMORY:-true}
MIN_MEMORY_MB=${MIN_MEMORY_MB:-1024}
MAX_MEMORY_PERCENT=${MAX_MEMORY_PERCENT:-75}
ENABLE_AUTO_SWAP=${ENABLE_AUTO_SWAP:-true}
SWAP_SIZE_MB=${SWAP_SIZE_MB:-4096}
GPU_MEMORY_FRACTION=${GPU_MEMORY_FRACTION:-0.7}
ENABLE_RESOURCE_MONITORING=${ENABLE_RESOURCE_MONITORING:-true}
RESOURCE_MONITOR_INTERVAL=${RESOURCE_MONITOR_INTERVAL:-30}

#################################
# HARDWARE DETECTION FUNCTIONS
#################################

# Detect Jetson model and JetPack version
detect_jetson() {
    echo -e "${BLUE}[INFO]${NC} Detecting Jetson hardware and software..."

    # Get Jetson model
    if [ -f "/proc/device-tree/model" ]; then
        JETSON_MODEL=$(cat /proc/device-tree/model | tr '\0' ' ' | xargs)
        echo -e "${GREEN}[DETECTED]${NC} Jetson model: ${JETSON_MODEL}"
    else
        JETSON_MODEL="Unknown Jetson"
        echo -e "${YELLOW}[WARNING]${NC} Unable to detect Jetson model"
    fi

    # Get JetPack version
    if [ -f "/etc/nv_tegra_release" ]; then
        JETPACK_VERSION=$(head -n 1 /etc/nv_tegra_release | grep -o 'R[0-9]*.[0-9]*.[0-9]*' | sed 's/R//')
        echo -e "${GREEN}[DETECTED]${NC} JetPack version: ${JETPACK_VERSION}"
    else
        JETPACK_VERSION="Unknown"
        echo -e "${YELLOW}[WARNING]${NC} Unable to detect JetPack version"
    fi

    # Detect CUDA version
    CUDA_VERSION=$(nvcc --version 2>/dev/null | grep "release" | awk '{print $6}' | sed 's/,//')
    if [ -n "$CUDA_VERSION" ]; then
        echo -e "${GREEN}[DETECTED]${NC} CUDA version: ${CUDA_VERSION}"
    else
        echo -e "${YELLOW}[WARNING]${NC} Unable to detect CUDA version"
    fi
}

# Detect DeepStream version and set paths
detect_deepstream() {
    echo -e "${BLUE}[INFO]${NC} Detecting DeepStream installation..."

    # Find DeepStream installation by checking common locations
    DS_DIRS=(
        "/opt/nvidia/deepstream/deepstream-6.3"
        "/opt/nvidia/deepstream/deepstream-6.2"
        "/opt/nvidia/deepstream/deepstream-6.1"
        "/opt/nvidia/deepstream/deepstream-6.0"
        "/opt/nvidia/deepstream"
    )

    DS_PATH=""
    DS_VERSION=""

    for dir in "${DS_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            DS_PATH="$dir"
            if [[ "$dir" == *"deepstream-"* ]]; then
                DS_VERSION=$(echo "$dir" | sed "s/.*deepstream-//")
            else
                DS_VERSION="unknown"
            fi
            echo -e "${GREEN}[FOUND]${NC} DeepStream installation: $DS_PATH (version $DS_VERSION)"
            break
        fi
    done

    if [ -z "$DS_PATH" ]; then
        echo -e "${YELLOW}[WARNING]${NC} DeepStream installation not found"
        return 1
    fi

    # Check if critical libraries are present
    echo -e "${BLUE}[INFO]${NC} Checking for critical DeepStream libraries..."
    
    CRITICAL_LIBS=(
        "libnvdsgst_meta.so"
        "libnvds_meta.so"
        "libnvstreammux.so"
        "libnvdsgst_helper.so"
        "libnvds_batch_jpegenc.so"
        "libnvds_nvmultiobjecttracker.so"
    )

    MISSING_LIBS=0
    for lib in "${CRITICAL_LIBS[@]}"; do
        if [ -f "$DS_PATH/lib/$lib" ]; then
            echo -e "${GREEN}[FOUND]${NC} $lib in $DS_PATH/lib"
        elif [ -f "$DS_PATH/lib/gst-plugins/$lib" ]; then
            echo -e "${GREEN}[FOUND]${NC} $lib in $DS_PATH/lib/gst-plugins"
        else
            echo -e "${YELLOW}[WARNING]${NC} $lib not found in DeepStream installation"
            MISSING_LIBS=$((MISSING_LIBS + 1))
        fi
    done

    if [ $MISSING_LIBS -gt 0 ]; then
        echo -e "${YELLOW}[WARNING]${NC} $MISSING_LIBS DeepStream libraries could not be found"
    fi

    # Store the original values to append
    ORIG_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
    ORIG_PATH="$PATH"
    ORIG_GST_PLUGIN_PATH="$GST_PLUGIN_PATH"
    ORIG_PYTHONPATH="$PYTHONPATH"
    
    # Clear variables and set with explicit paths to avoid duplicates
    export LD_LIBRARY_PATH="$DS_PATH/lib:$DS_PATH/lib/gst-plugins"
    if [ -n "$ORIG_LD_LIBRARY_PATH" ]; then
        export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$ORIG_LD_LIBRARY_PATH"
    fi
    
    export PATH="$DS_PATH/bin"
    if [ -n "$ORIG_PATH" ]; then
        export PATH="$PATH:$ORIG_PATH"
    fi
    
    export GST_PLUGIN_PATH="$DS_PATH/lib/gst-plugins:/usr/lib/aarch64-linux-gnu/gstreamer-1.0"
    if [ -n "$ORIG_GST_PLUGIN_PATH" ]; then
        export GST_PLUGIN_PATH="$GST_PLUGIN_PATH:$ORIG_GST_PLUGIN_PATH"
    fi
    
    if [ -d "$DS_PATH/sources/deepstream_python_apps" ]; then
        export PYTHONPATH="$DS_PATH/sources/deepstream_python_apps:$DS_PATH/sources/deepstream_python_apps/bindings"
        if [ -n "$ORIG_PYTHONPATH" ]; then
            export PYTHONPATH="$PYTHONPATH:$ORIG_PYTHONPATH"
        fi
    fi
    
    # Export DeepStream paths for other scripts
    export DS_PATH
    export DS_VERSION
    
    # Create system-wide environment script
    echo -e "${BLUE}[INFO]${NC} Creating system-wide environment script..."
    
    mkdir -p /etc/profile.d
    cat > /etc/profile.d/deepstream.sh << EOF
#!/bin/bash
# DeepStream environment setup
export DS_PATH="$DS_PATH"
export DS_VERSION="$DS_VERSION"
export LD_LIBRARY_PATH="$DS_PATH/lib:$DS_PATH/lib/gst-plugins:\$LD_LIBRARY_PATH"
export PATH="$DS_PATH/bin:\$PATH"
export GST_PLUGIN_PATH="$DS_PATH/lib/gst-plugins:/usr/lib/aarch64-linux-gnu/gstreamer-1.0:\$GST_PLUGIN_PATH"
export PYTHONPATH="$DS_PATH/sources/deepstream_python_apps:$DS_PATH/sources/deepstream_python_apps/bindings:\$PYTHONPATH"
EOF
    
    chmod +x /etc/profile.d/deepstream.sh
    
    # Create .bashrc entry for interactive shells
    if [ -f "$HOME/.bashrc" ]; then
        if ! grep -q "deepstream.sh" "$HOME/.bashrc"; then
            echo -e "${BLUE}[INFO]${NC} Adding DeepStream environment to .bashrc..."
            echo "" >> "$HOME/.bashrc"
            echo "# DeepStream environment setup" >> "$HOME/.bashrc"
            echo "if [ -f /etc/profile.d/deepstream.sh ]; then" >> "$HOME/.bashrc"
            echo "  . /etc/profile.d/deepstream.sh" >> "$HOME/.bashrc"
            echo "fi" >> "$HOME/.bashrc"
        fi
    fi
    
    # Create a run-deepstream wrapper script
    echo -e "${BLUE}[INFO]${NC} Creating DeepStream wrapper script..."
    
    mkdir -p /usr/local/bin
    cat > /usr/local/bin/run-deepstream << EOF
#!/bin/bash
# DeepStream Application Runner

# Set up DeepStream environment
export DS_PATH="$DS_PATH"
export DS_VERSION="$DS_VERSION"
export LD_LIBRARY_PATH="$DS_PATH/lib:$DS_PATH/lib/gst-plugins:\$LD_LIBRARY_PATH"
export PATH="$DS_PATH/bin:\$PATH"
export GST_PLUGIN_PATH="$DS_PATH/lib/gst-plugins:/usr/lib/aarch64-linux-gnu/gstreamer-1.0:\$GST_PLUGIN_PATH"
export PYTHONPATH="$DS_PATH/sources/deepstream_python_apps:$DS_PATH/sources/deepstream_python_apps/bindings:\$PYTHONPATH"

# Run the command with proper environment
exec "\$@"
EOF
    
    chmod +x /usr/local/bin/run-deepstream
    
    echo -e "${GREEN}[SUCCESS]${NC} DeepStream environment setup complete"
    
    # Return success
    return 0
}

# Detect available hardware accelerators
detect_accelerators() {
    echo -e "${BLUE}[INFO]${NC} Detecting hardware accelerators..."
    ACCELERATORS=""

    # Check for GPU
    if [ -e "/dev/nvhost-gpu" ]; then
        ACCELERATORS+="GPU "
    fi

    # Check for NVDEC
    if [ -e "/dev/nvhost-nvdec" ]; then
        ACCELERATORS+="NVDEC "
    fi

    # Check for NVENC/MSENC
    if [ -e "/dev/nvhost-msenc" ]; then
        ACCELERATORS+="NVENC "
    fi

    # Check for NVJPG
    if [ -e "/dev/nvhost-nvjpg" ]; then
        ACCELERATORS+="NVJPG "
    fi

    # Check for VIC
    if [ -e "/dev/nvhost-vic" ]; then
        ACCELERATORS+="VIC "
    fi

    # Check for DLA
    if [ -e "/dev/nvhost-nvdla0" ] || [ -e "/dev/nvhost-nvdla1" ]; then
        ACCELERATORS+="DLA "
    fi

    # Check for PVA
    if [ -e "/dev/nvhost-pva0" ] || [ -e "/dev/nvhost-pva1" ]; then
        ACCELERATORS+="PVA "
    fi

    if [ -n "$ACCELERATORS" ]; then
        echo -e "${GREEN}[DETECTED]${NC} Hardware accelerators: ${ACCELERATORS}"
    else
        echo -e "${YELLOW}[WARNING]${NC} No hardware accelerators detected"
    fi
}

# Detect power mode
detect_power_mode() {
    if [[ "$JETSON_MODEL" == *"Orin"* ]]; then
        if [ -f "/sys/devices/gpu.0/power/control" ]; then
            POWER_MODE=$(cat /sys/devices/gpu.0/power/control)
            echo -e "${GREEN}[DETECTED]${NC} Power mode: ${POWER_MODE}"
        elif [ -f "/sys/devices/platform/13800000.mali/power/control" ]; then
            POWER_MODE=$(cat /sys/devices/platform/13800000.mali/power/control)
            echo -e "${GREEN}[DETECTED]${NC} Power mode: ${POWER_MODE}"
        else
            POWER_MODE="unknown"
            echo -e "${YELLOW}[WARNING]${NC} Unable to detect power mode"
        fi
    else
        # For non-Orin devices
        POWER_MODE="auto"
        echo -e "${BLUE}[INFO]${NC} Power mode detection not applicable for this device"
    fi
}

#################################
# RESOURCE MANAGEMENT FUNCTIONS
#################################

# Get total system memory in MB
get_total_memory() {
    local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    echo $((mem_total / 1024))
}

# Get available system memory in MB
get_available_memory() {
    local mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    echo $((mem_available / 1024))
}

# Get total system swap in MB
get_total_swap() {
    local swap_total=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
    echo $((swap_total / 1024))
}

# Configure memory limits based on system resources
configure_memory_limits() {
    echo -e "${BLUE}[INFO]${NC} Configuring memory management..."
    
    # Get system memory
    TOTAL_MEM_MB=$(get_total_memory)
    AVAILABLE_MEM_MB=$(get_available_memory)
    TOTAL_SWAP_MB=$(get_total_swap)
    
    echo -e "${GREEN}[DETECTED]${NC} System memory: ${TOTAL_MEM_MB} MB total, ${AVAILABLE_MEM_MB} MB available"
    
    # Calculate container memory limit (75% of total by default, configurable)
    CONTAINER_MEM_LIMIT=$((TOTAL_MEM_MB * MAX_MEMORY_PERCENT / 100))
    
    # Ensure minimum memory is allocated
    if [ $CONTAINER_MEM_LIMIT -lt $MIN_MEMORY_MB ]; then
        CONTAINER_MEM_LIMIT=$MIN_MEMORY_MB
        echo -e "${YELLOW}[WARNING]${NC} Calculated memory limit too low, using minimum: ${MIN_MEMORY_MB} MB"
    fi
    
    echo -e "${GREEN}[CONFIGURED]${NC} Container memory limit: ${CONTAINER_MEM_LIMIT} MB"
    
    # Create memory allocation profile for the container
    cat > /usr/local/bin/memory-profile << EOF
#!/bin/bash
echo "Memory Profile:"
echo "Total System Memory: ${TOTAL_MEM_MB} MB"
echo "Available System Memory: ${AVAILABLE_MEM_MB} MB"
echo "Container Memory Limit: ${CONTAINER_MEM_LIMIT} MB"
echo "Total System Swap: ${TOTAL_SWAP_MB} MB"
EOF
    chmod +x /usr/local/bin/memory-profile
}

# Configure GPU memory management
configure_gpu_memory() {
    echo -e "${BLUE}[INFO]${NC} Configuring GPU memory management..."
    
    # Export CUDA_DEVICE_MAX_CONNECTIONS for better memory management
    export CUDA_DEVICE_MAX_CONNECTIONS=1
    
    # Set custom environment variable for TensorRT memory allocator
    export TRT_MEMORY_FRACTION=$GPU_MEMORY_FRACTION
    
    # For TensorFlow GPU memory 
    export TF_MEMORY_ALLOCATION=$GPU_MEMORY_FRACTION
    export TF_GPU_ALLOCATOR=cuda_malloc_async
    
    # For PyTorch memory management
    export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512
    
    echo -e "${GREEN}[CONFIGURED]${NC} GPU memory fraction: ${GPU_MEMORY_FRACTION}"
}

# Create and configure swap if needed
configure_swap() {
    if [ "$ENABLE_AUTO_SWAP" = "true" ]; then
        echo -e "${BLUE}[INFO]${NC} Checking swap configuration..."
        
        # Check if swap already exists
        if [ $TOTAL_SWAP_MB -gt 0 ]; then
            echo -e "${GREEN}[INFO]${NC} System already has ${TOTAL_SWAP_MB} MB swap space"
        else
            # Check if we have access to create swap
            if [ -d "/swap" ] && touch /swap/test_access && rm /swap/test_access; then
                echo -e "${BLUE}[INFO]${NC} Creating swap file with size ${SWAP_SIZE_MB} MB..."
                
                # Create swap file
                dd if=/dev/zero of=/swap/swapfile bs=1M count=$SWAP_SIZE_MB status=progress
                chmod 600 /swap/swapfile
                mkswap /swap/swapfile
                swapon /swap/swapfile
                
                # Verify swap is enabled
                NEW_SWAP_MB=$(get_total_swap)
                if [ $NEW_SWAP_MB -gt 0 ]; then
                    echo -e "${GREEN}[SUCCESS]${NC} Created and activated ${NEW_SWAP_MB} MB swap space"
                else
                    echo -e "${YELLOW}[WARNING]${NC} Failed to create swap space"
                fi
            else
                echo -e "${YELLOW}[WARNING]${NC} Cannot create swap file, insufficient permissions or storage"
            fi
        fi
    else
        echo -e "${BLUE}[INFO]${NC} Auto swap creation disabled"
    fi
}

# Create a resource monitoring daemon
create_resource_monitor() {
    if [ "$ENABLE_RESOURCE_MONITORING" = "true" ]; then
        echo -e "${BLUE}[INFO]${NC} Setting up resource monitoring daemon..."
        
        # Create monitoring script
        cat > /usr/local/bin/resource-monitor << 'EOF'
#!/bin/bash
INTERVAL=${1:-30}
LOG_FILE="/advantech/logs/resources.log"

# Ensure log directory exists
mkdir -p $(dirname $LOG_FILE)

# Function to log stats with timestamp
log_stats() {
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    MEM_STATS=$(free -m | awk 'NR==2{printf "Mem: %s/%sMB (%.2f%%)", $3, $2, $3*100/$2}')
    CPU_STATS=$(top -bn1 | awk 'NR>7{sum+=$9} END {printf "CPU: %.1f%%", sum}')
    DISK_STATS=$(df -h /advantech | awk 'NR==2{printf "Disk: %s/%s (%.1f%%)", $3, $2, $5}' | sed 's/%//')
    
    # Try to get GPU stats if available
    if command -v nvidia-smi &> /dev/null; then
        GPU_STATS=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits | awk -F', ' '{printf "GPU: %s%% util, %sMB/%sMB", $1, $2, $3}')
    else
        # Alternative for Jetson
        if [ -f "/sys/devices/gpu.0/load" ]; then
            GPU_LOAD=$(cat /sys/devices/gpu.0/load)
            GPU_STATS="GPU: ${GPU_LOAD}% util"
        else
            GPU_STATS="GPU: stats unavailable"
        fi
    fi
    
    echo "${TIMESTAMP} | ${MEM_STATS} | ${CPU_STATS} | ${GPU_STATS} | ${DISK_STATS}" >> $LOG_FILE
}

echo "Starting resource monitoring with ${INTERVAL}s interval. Logging to ${LOG_FILE}"
echo "# Resource Monitoring Started: $(date)" > $LOG_FILE
echo "# Interval: ${INTERVAL}s" >> $LOG_FILE
echo "# Format: Timestamp | Memory | CPU | GPU | Disk" >> $LOG_FILE

while true; do
    log_stats
    sleep $INTERVAL
done
EOF
        chmod +x /usr/local/bin/resource-monitor
        
        # Start monitoring daemon in background
        /usr/local/bin/resource-monitor $RESOURCE_MONITOR_INTERVAL &
        echo -e "${GREEN}[STARTED]${NC} Resource monitoring daemon (interval: ${RESOURCE_MONITOR_INTERVAL}s)"
    fi
}

# Create memory optimization tools
create_memory_tools() {
    echo -e "${BLUE}[INFO]${NC} Creating memory optimization tools..."
    
    # Script to clear cache and buffers
    cat > /usr/local/bin/clear-memory << 'EOF'
#!/bin/bash
# Force clear cache and buffers
echo "Clearing memory caches and buffers..."
sync
echo 3 > /proc/sys/vm/drop_caches
echo "Memory cleared. Current memory status:"
free -m
EOF
    chmod +x /usr/local/bin/clear-memory
    
    # Script to optimize for GPU processing
    cat > /usr/local/bin/optimize-for-gpu << 'EOF'
#!/bin/bash
# Free system memory and optimize settings for GPU processing
echo "Optimizing system for GPU processing..."
sync
echo 1 > /proc/sys/vm/drop_caches
echo 10 > /proc/sys/vm/swappiness
echo "Current CUDA devices:"
ls -la /dev/nvidia*
echo "Memory status after optimization:"
free -m
EOF
    chmod +x /usr/local/bin/optimize-for-gpu
    
    # Script to throttle CPU for better GPU performance
    cat > /usr/local/bin/throttle-cpu << 'EOF'
#!/bin/bash
# Temporarily reduce CPU priority to give more resources to GPU
echo "Throttling CPU to prioritize GPU processing..."
PID=${1:-$$}
renice 10 -p $PID
echo "Process $PID now has reduced CPU priority"
EOF
    chmod +x /usr/local/bin/throttle-cpu
}

#################################
# DEEPSTREAM TOOLS CREATION
#################################

# Create DeepStream diagnostic tool
create_deepstream_tools() {
    echo -e "${BLUE}[INFO]${NC} Creating DeepStream diagnostic tools..."

    # Create DS check script
    cat > /usr/local/bin/ds-check << 'EOF'
#!/bin/bash
# DeepStream Diagnostic Tool

# Terminal colors
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m"

echo -e "${BLUE}DeepStream Installation Check${NC}"
echo "=============================="

# Source environment setup
if [ -f "/etc/profile.d/deepstream.sh" ]; then
    source /etc/profile.d/deepstream.sh
fi

# Check DeepStream installation
if [ -n "$DS_PATH" ] && [ -d "$DS_PATH" ]; then
    echo -e "${GREEN}DeepStream path:${NC} $DS_PATH"
    echo -e "${GREEN}DeepStream version:${NC} $DS_VERSION"
    
    # Check DeepStream version details
    if [ -f "$DS_PATH/version" ]; then
        echo -e "${GREEN}Version details:${NC} $(cat $DS_PATH/version)"
    fi
    
    # Check libraries count
    LIB_COUNT=$(find $DS_PATH/lib -name "*.so*" 2>/dev/null | wc -l)
    echo -e "${GREEN}Libraries:${NC} $LIB_COUNT files"
    
    # Check binaries count
    BIN_COUNT=$(find $DS_PATH/bin -type f -executable 2>/dev/null | wc -l)
    echo -e "${GREEN}Binaries:${NC} $BIN_COUNT files"
    
    # Check GStreamer plugins count
    GST_COUNT=$(find $DS_PATH/lib/gst-plugins -name "*.so*" 2>/dev/null | wc -l)
    echo -e "${GREEN}GStreamer plugins:${NC} $GST_COUNT files"
else
    echo -e "${RED}DeepStream installation not found!${NC}"
    exit 1
fi

# Check environment variables
echo -e "\n${BLUE}DeepStream environment variables:${NC}"
echo -e "${GREEN}LD_LIBRARY_PATH:${NC} $LD_LIBRARY_PATH"
echo -e "${GREEN}GST_PLUGIN_PATH:${NC} $GST_PLUGIN_PATH"
echo -e "${GREEN}PATH:${NC} $PATH"
echo -e "${GREEN}PYTHONPATH:${NC} $PYTHONPATH"

# Check critical libraries
echo -e "\n${BLUE}Checking for critical DeepStream libraries:${NC}"
MISSING_LIBS=0

for lib in libnvdsgst_meta.so libnvds_meta.so libnvstreammux.so libnvdsgst_helper.so libnvds_batch_jpegenc.so libnvds_nvmultiobjecttracker.so; do
    LIB_FOUND=0
    
    # Check in DeepStream lib directory
    if [ -f "$DS_PATH/lib/$lib" ]; then
        echo -e "${GREEN}✓${NC} $lib: $DS_PATH/lib/$lib"
        LIB_FOUND=1
    # Check in DeepStream gst-plugins directory
    elif [ -f "$DS_PATH/lib/gst-plugins/$lib" ]; then
        echo -e "${GREEN}✓${NC} $lib: $DS_PATH/lib/gst-plugins/$lib"
        LIB_FOUND=1
    fi
    
    if [ $LIB_FOUND -eq 0 ]; then
        echo -e "${RED}✗${NC} $lib: Not found"
        MISSING_LIBS=$((MISSING_LIBS + 1))
    fi
done

if [ $MISSING_LIBS -gt 0 ]; then
    echo -e "${RED}[WARNING]${NC} Missing libraries in system path: $MISSING_LIBS"
else
    echo -e "${GREEN}All critical libraries found${NC}"
fi

# Check DeepStream GStreamer plugins
echo -e "\n${BLUE}Checking DeepStream GStreamer plugins:${NC}"
if command -v gst-inspect-1.0 >/dev/null 2>&1; then
    MISSING_PLUGINS=0
    
    for plugin in nvstreammux nvinfer nvvideoconvert nvdsosd; do
        if gst-inspect-1.0 $plugin >/dev/null 2>&1; then
            PLUGIN_PATH=$(gst-inspect-1.0 $plugin 2>/dev/null | grep "Filename" | head -1 | sed 's/Filename: //')
            echo -e "${GREEN}✓${NC} $plugin plugin is available: $PLUGIN_PATH"
        else
            echo -e "${RED}✗${NC} $plugin plugin is NOT available"
            MISSING_PLUGINS=$((MISSING_PLUGINS + 1))
        fi
    done
    
    if [ $MISSING_PLUGINS -gt 0 ]; then
        echo -e "${RED}[WARNING]${NC} Missing $MISSING_PLUGINS GStreamer plugins"
    else
        echo -e "${GREEN}All required GStreamer plugins available${NC}"
    fi
else
    echo -e "${RED}✗${NC} gst-inspect-1.0 not found, cannot check plugins"
fi

# Test a simple GStreamer pipeline
echo -e "\n${BLUE}Testing simple GStreamer pipeline:${NC}"
if command -v gst-launch-1.0 >/dev/null 2>&1; then
    if timeout 5 gst-launch-1.0 videotestsrc num-buffers=10 ! fakesink >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Basic GStreamer pipeline works"
        
        # Try with NVIDIA plugins if they seem available
        if [ $MISSING_PLUGINS -eq 0 ]; then
            if timeout 5 gst-launch-1.0 videotestsrc num-buffers=10 ! nvvideoconvert ! fakesink >/dev/null 2>&1; then
                echo -e "${GREEN}✓${NC} NVIDIA GStreamer elements work"
            else
                echo -e "${RED}✗${NC} NVIDIA GStreamer elements test failed"
            fi
        fi
    else
        echo -e "${RED}✗${NC} Basic GStreamer pipeline failed"
    fi
else
    echo -e "${RED}✗${NC} gst-launch-1.0 not found"
fi

# Check DeepStream application
echo -e "\n${BLUE}Checking DeepStream application:${NC}"
if command -v deepstream-app >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} deepstream-app found: $(which deepstream-app)"
    
    # Try to get version info
    DS_VERSION_INFO=$(timeout 2 deepstream-app --version-all 2>&1 | grep -v "ERROR")
    if [ -n "$DS_VERSION_INFO" ]; then
        echo -e "${GREEN}✓${NC} DeepStream version info: $DS_VERSION_INFO"
    fi
else
    if [ -x "$DS_PATH/bin/deepstream-app" ]; then
        echo -e "${YELLOW}!${NC} deepstream-app found but not in PATH: $DS_PATH/bin/deepstream-app"
        echo -e "${YELLOW}!${NC} Use run-deepstream to execute DeepStream applications"
    else
        echo -e "${RED}✗${NC} deepstream-app not found"
    fi
fi

# Suggest fixes if there are issues
if [ $MISSING_LIBS -gt 0 ] || [ $MISSING_PLUGINS -gt 0 ]; then
    echo -e "\n${BLUE}Suggested fixes:${NC}"
    echo -e "${YELLOW}1. Use run-deepstream wrapper for all DeepStream applications:${NC}"
    echo -e "   run-deepstream <your-command>"
    echo -e "${YELLOW}2. Make sure DeepStream paths are properly set in your environment:${NC}"
    echo -e "   source /etc/profile.d/deepstream.sh"
    echo -e "${YELLOW}3. Check if DeepStream libraries are correctly installed:${NC}"
    echo -e "   ls -la $DS_PATH/lib"
    echo -e "   ls -la $DS_PATH/lib/gst-plugins"
fi
EOF
    chmod +x /usr/local/bin/ds-check

    # Create DeepStream help script
    cat > /usr/local/bin/deepstream-help << 'EOF'
#!/bin/bash

# Colors for better readability
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m"

echo -e "${BLUE}=== Advantech Edge AI Container with DeepStream Support ===${NC}"
echo ""
echo -e "${BLUE}DeepStream utilities:${NC}"
echo -e "  ${GREEN}run-deepstream${NC}     - Run DeepStream applications with proper environment"
echo -e "                       Example: run-deepstream deepstream-app -c config.txt"
echo -e "  ${GREEN}ds-check${NC}           - Check DeepStream installation and configuration"
echo ""
echo -e "${BLUE}System utilities:${NC}"
echo -e "  ${GREEN}analyze-system${NC}     - Print detailed system information"
echo -e "  ${GREEN}gpu-monitor${NC}        - Monitor GPU usage"
echo -e "  ${GREEN}resource-manager${NC}   - Manage system resources"
echo -e "  ${GREEN}container-info${NC}     - Show container configuration"
echo -e "  ${GREEN}optimize-for-gpu${NC}   - Optimize system for GPU processing"
echo ""
echo -e "${BLUE}Usage examples:${NC}"
echo -e "  ${YELLOW}ds-check${NC}                        - Check DeepStream installation"
echo -e "  ${YELLOW}run-deepstream python3 app.py${NC}    - Run a Python DeepStream application"
echo -e "  ${YELLOW}run-deepstream gst-launch-1.0 videotestsrc ! nvvideoconvert ! fakesink${NC} - Test a pipeline"
echo ""
echo -e "${BLUE}Troubleshooting tips:${NC}"
echo -e "  - If DeepStream libraries are missing, always use ${YELLOW}run-deepstream${NC} wrapper"
echo -e "  - Use ${YELLOW}source /etc/profile.d/deepstream.sh${NC} to set up environment in new shells"
echo -e "  - Check logs in /advantech/logs for diagnostic information"
echo "===================================================="
EOF
    chmod +x /usr/local/bin/deepstream-help
}

# Create container info script
create_container_info() {
    cat > /usr/local/bin/container-info << EOF
#!/bin/bash
echo "=== Advantech Jetson AI Container ==="
echo "Jetson Model: ${JETSON_MODEL}"
echo "JetPack Version: ${JETPACK_VERSION}"
echo "CUDA Version: ${CUDA_VERSION}"
echo "DeepStream Version: ${DS_VERSION}"
echo "DeepStream Path: ${DS_PATH}"
echo "Power Mode: ${POWER_MODE}"
echo ""
echo "Available Hardware Accelerators:"
for acc in ${ACCELERATORS}; do
    echo " - \$acc: Available"
done
echo ""
echo "Resource Management:"
echo "Memory Limit: ${CONTAINER_MEM_LIMIT} MB"
echo "GPU Memory Fraction: ${GPU_MEMORY_FRACTION}"
if [ "$ENABLE_AUTO_SWAP" = "true" ]; then
    echo "Auto Swap: Enabled ($(get_total_swap) MB)"
else
    echo "Auto Swap: Disabled"
fi
if [ "$ENABLE_RESOURCE_MONITORING" = "true" ]; then
    echo "Resource Monitoring: Enabled (${RESOURCE_MONITOR_INTERVAL}s interval)"
    echo "Monitoring Log: /advantech/logs/resources.log"
fi
echo ""
echo "Utilities:"
echo "  deepstream-help    - Show DeepStream usage information"
echo "  ds-check          - Check DeepStream installation and configuration"
echo "  run-deepstream    - Run applications with DeepStream environment"
echo "  clear-memory      - Clear memory caches and buffers"
echo "  optimize-for-gpu  - Optimize memory for GPU processing"
echo "  throttle-cpu      - Reduce CPU priority for a process"
echo "  memory-profile    - Show memory allocation profile"
echo "===================================="
EOF
    chmod +x /usr/local/bin/container-info
}

#################################
# MAIN EXECUTION
#################################

# Create necessary directories
mkdir -p /advantech/models /advantech/src /advantech/config /advantech/logs

# Run detection functions
detect_jetson
detect_deepstream
detect_accelerators
detect_power_mode

# Configure system resources
if [ "$ENABLE_DYNAMIC_MEMORY" = "true" ]; then
    configure_memory_limits
    configure_gpu_memory
    configure_swap
fi

# Create helper scripts
create_memory_tools
create_deepstream_tools
create_container_info

# Start resource monitoring if enabled
if [ "$ENABLE_RESOURCE_MONITORING" = "true" ]; then
    create_resource_monitor
fi

# Start resource and GPU monitoring if enabled
if [ "$ENABLE_RESOURCE_MONITORING" = "true" ] && [ -x "/usr/local/bin/resource-manager" ]; then
    echo -e "${BLUE}[INFO]${NC} Starting resource monitoring services..."
    
    # Start resource manager in background
    /usr/local/bin/resource-manager > /dev/null 2>&1 &
    echo -e "${GREEN}[STARTED]${NC} Resource Manager (PID: $!)"
    
    # Start GPU monitoring in background if available
    if [ -x "/usr/local/bin/gpu-monitor" ]; then
        /usr/local/bin/gpu-monitor > /dev/null 2>&1 &
        echo -e "${GREEN}[STARTED]${NC} GPU Monitor (PID: $!)"
    fi
fi

# Summary
echo -e "${BLUE}=====================================================${NC}"
echo -e "${GREEN}[READY]${NC} Advantech Jetson AI container initialized"
echo -e "${BLUE}[INFO]${NC} Jetson: ${JETSON_MODEL}"
echo -e "${BLUE}[INFO]${NC} JetPack: ${JETPACK_VERSION}"
echo -e "${BLUE}[INFO]${NC} DeepStream: ${DS_VERSION}"
if [ "$ENABLE_DYNAMIC_MEMORY" = "true" ]; then
    echo -e "${BLUE}[INFO]${NC} Memory Management: Active (${CONTAINER_MEM_LIMIT} MB limit)"
    echo -e "${BLUE}[INFO]${NC} GPU Memory Fraction: ${GPU_MEMORY_FRACTION}"
fi
echo -e "${BLUE}[INFO]${NC} Run 'container-info' for detailed information"
echo -e "${BLUE}[INFO]${NC} Run 'deepstream-help' for DeepStream usage guide"
echo -e "${BLUE}=====================================================${NC}"

# Execute the command passed to the script
exec "$@"