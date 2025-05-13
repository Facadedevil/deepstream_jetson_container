#!/bin/bash
# Advanced Resource manager script for Jetson devices

# Set default values
INTERVAL=${INTERVAL:-5}                  # Check every 5 seconds
LOG_FILE="/advantech/logs/resource-usage.log"
MEMORY_HIGH="${MEMORY_HIGH:-6000}"       # High threshold for memory in MB (default: 6GB)
MEMORY_LOW="${MEMORY_LOW:-3000}"         # Low threshold for memory in MB (default: 3GB)
GPU_HIGH="${GPU_HIGH:-85}"               # High threshold for GPU in % (default: 85%)
CPU_HIGH="${CPU_HIGH:-85}"               # High threshold for CPU in % (default: 85%)
GPU_THROTTLE_TEMP="${GPU_THROTTLE_TEMP:-80}" # Temperature at which to throttle GPU (default: 80°C)

# Terminal colors for log readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Create log directory if it doesn't exist
mkdir -p $(dirname $LOG_FILE)

# Log start
echo -e "${BLUE}[$(date)]${NC} Resource Manager started" > $LOG_FILE
echo -e "${BLUE}[$(date)]${NC} Memory thresholds: HIGH=${MEMORY_HIGH}MB, LOW=${MEMORY_LOW}MB" >> $LOG_FILE
echo -e "${BLUE}[$(date)]${NC} GPU threshold: HIGH=${GPU_HIGH}%, Throttle temp: ${GPU_THROTTLE_TEMP}°C" >> $LOG_FILE
echo -e "${BLUE}[$(date)]${NC} CPU threshold: HIGH=${CPU_HIGH}%" >> $LOG_FILE

# Function to log resource usage
log_resources() {
    # Memory info
    MEM_TOTAL=$(free -m | grep Mem | awk '{print $2}')
    MEM_USED=$(free -m | grep Mem | awk '{print $3}')
    MEM_FREE=$(free -m | grep Mem | awk '{print $4}')
    MEM_USAGE_PCT=$((MEM_USED * 100 / MEM_TOTAL))
    
    # CPU usage
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
    
    # GPU usage
    GPU_USAGE=$(cat /sys/devices/gpu.0/load 2>/dev/null || echo "N/A")
    if [ "$GPU_USAGE" != "N/A" ]; then
        GPU_USAGE_VAL=$GPU_USAGE
        GPU_USAGE="${GPU_USAGE}%"
    else
        GPU_USAGE_VAL=0
    fi
    
    # GPU Temperature
    GPU_TEMP="N/A"
    if [ -f "/sys/devices/virtual/thermal/thermal_zone*/type" ]; then
        # Find the GPU thermal zone
        gpu_zone=$(grep -l "GPU" /sys/devices/virtual/thermal/thermal_zone*/type | head -1 | sed 's/\/type$//')
        if [ -n "$gpu_zone" ] && [ -f "${gpu_zone}/temp" ]; then
            GPU_TEMP=$(($(cat ${gpu_zone}/temp) / 1000))
            GPU_TEMP="${GPU_TEMP}°C"
        fi
    fi
    
    # Log with color coding based on usage
    if [ $MEM_USAGE_PCT -gt 90 ]; then
        MEM_COLOR=$RED
    elif [ $MEM_USAGE_PCT -gt 70 ]; then
        MEM_COLOR=$YELLOW
    else
        MEM_COLOR=$GREEN
    fi
    
    if [ $(echo "$CPU_USAGE > 90" | bc 2>/dev/null || echo "0") -eq 1 ]; then
        CPU_COLOR=$RED
    elif [ $(echo "$CPU_USAGE > 70" | bc 2>/dev/null || echo "0") -eq 1 ]; then
        CPU_COLOR=$YELLOW
    else
        CPU_COLOR=$GREEN
    fi
    
    if [ "$GPU_USAGE_VAL" != "N/A" ] && [ $GPU_USAGE_VAL -gt 90 ]; then
        GPU_COLOR=$RED
    elif [ "$GPU_USAGE_VAL" != "N/A" ] && [ $GPU_USAGE_VAL -gt 70 ]; then
        GPU_COLOR=$YELLOW
    else
        GPU_COLOR=$GREEN
    fi
    
    echo -e "${BLUE}[$(date)]${NC} MEM=${MEM_COLOR}${MEM_USED}MB/${MEM_TOTAL}MB (${MEM_USAGE_PCT}%)${NC}, CPU=${CPU_COLOR}${CPU_USAGE}%${NC}, GPU=${GPU_COLOR}${GPU_USAGE}${NC}, Temp=${GPU_TEMP}" >> $LOG_FILE
}

# Function to check if action is needed based on memory usage
check_memory() {
    MEM_USED=$(free -m | grep Mem | awk '{print $3}')
    
    # Check if memory usage is above high threshold
    if [ $MEM_USED -gt $MEMORY_HIGH ]; then
        echo -e "${RED}[$(date)] WARNING${NC} - Memory usage high (${MEM_USED}MB > ${MEMORY_HIGH}MB), taking action" >> $LOG_FILE
        
        # Clear cached memory
        sync
        echo 3 > /proc/sys/vm/drop_caches
        
        # Find and log top memory processes
        echo -e "${YELLOW}Top memory processes:${NC}" >> $LOG_FILE
        ps aux --sort=-%mem | head -5 >> $LOG_FILE
        
        # Check for potential memory leaks in Python applications
        PYTHON_MEM=$(ps aux | grep python | grep -v grep | awk '{sum += $6} END {print sum/1024}')
        if [ $(echo "$PYTHON_MEM > 1000" | bc 2>/dev/null || echo "0") -eq 1 ]; then
            echo -e "${RED}[$(date)] WARNING${NC} - Python using ${PYTHON_MEM}MB of memory (potential leak)" >> $LOG_FILE
            
            # Identify the specific Python process using the most memory
            PYTHON_HEAVY=$(ps aux | grep python | grep -v grep | sort -k6 -r | head -1)
            echo -e "${YELLOW}Heaviest Python process:${NC} $PYTHON_HEAVY" >> $LOG_FILE
            
            # Log Python memory usage over time to detect leaks
            PID=$(echo $PYTHON_HEAVY | awk '{print $2}')
            if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
                MEM_MAPS_SIZE=$(cat /proc/$PID/smaps_rollup 2>/dev/null | grep -i "Rss" | awk '{print $2}' || echo "Unknown")
                echo -e "${YELLOW}Process $PID memory details:${NC} RSS=${MEM_MAPS_SIZE}kB" >> $LOG_FILE
            fi
        fi
    fi
}

# Function to check GPU usage and temperature
check_gpu() {
    # Check GPU Usage
    if [ -f "/sys/devices/gpu.0/load" ]; then
        GPU_USAGE=$(cat /sys/devices/gpu.0/load)
        
        if [ $GPU_USAGE -gt $GPU_HIGH ]; then
            echo -e "${RED}[$(date)] WARNING${NC} - GPU usage high (${GPU_USAGE}% > ${GPU_HIGH}%)" >> $LOG_FILE
            
            # Find GPU-intensive processes
            echo -e "${YELLOW}GPU-intensive processes:${NC}" >> $LOG_FILE
            ps aux | grep -E "deepstream|yolo|tensorflow|python|inference" | grep -v grep | head -3 >> $LOG_FILE
        fi
    fi
    
    # Check GPU Temperature
    if [ -f "/sys/devices/virtual/thermal/thermal_zone*/type" ]; then
        gpu_zone=$(grep -l "GPU" /sys/devices/virtual/thermal/thermal_zone*/type | head -1 | sed 's/\/type$//')
        if [ -n "$gpu_zone" ] && [ -f "${gpu_zone}/temp" ]; then
            GPU_TEMP=$(($(cat ${gpu_zone}/temp) / 1000))
            
            if [ $GPU_TEMP -gt $GPU_THROTTLE_TEMP ]; then
                echo -e "${RED}[$(date)] WARNING${NC} - GPU temperature critical (${GPU_TEMP}°C > ${GPU_THROTTLE_TEMP}°C)" >> $LOG_FILE
                
                # Log thermal zones
                echo -e "${YELLOW}All thermal zones:${NC}" >> $LOG_FILE
                for zone in /sys/devices/virtual/thermal/thermal_zone*; do
                    if [ -f "$zone/type" ] && [ -f "$zone/temp" ]; then
                        ZONE_TYPE=$(cat $zone/type)
                        ZONE_TEMP=$(($(cat $zone/temp) / 1000))
                        echo "  $ZONE_TYPE: ${ZONE_TEMP}°C" >> $LOG_FILE
                    fi
                done
                
                # Take action to reduce GPU load
                echo -e "${YELLOW}[$(date)] ACTION${NC} - Requesting GPU throttling due to high temperature" >> $LOG_FILE
                
                # Set GPU governor to throttle if available
                if [ -f "/sys/devices/gpu.0/devfreq/gpu.0/governor" ]; then
                    echo "powersave" > /sys/devices/gpu.0/devfreq/gpu.0/governor 2>/dev/null || true
                    echo -e "${YELLOW}[$(date)] ACTION${NC} - Set GPU governor to powersave mode" >> $LOG_FILE
                fi
                
                # Log current frequency
                if [ -f "/sys/devices/gpu.0/devfreq/gpu.0/cur_freq" ]; then
                    GPU_FREQ=$(($(cat /sys/devices/gpu.0/devfreq/gpu.0/cur_freq) / 1000000))
                    echo -e "${YELLOW}Current GPU frequency:${NC} ${GPU_FREQ}MHz" >> $LOG_FILE
                fi
            elif [ -f "/sys/devices/gpu.0/devfreq/gpu.0/governor" ] && [ $(cat /sys/devices/gpu.0/devfreq/gpu.0/governor) = "powersave" ] && [ $GPU_TEMP -lt $((GPU_THROTTLE_TEMP - 10)) ]; then
                # If temperature has dropped sufficiently, restore normal operation
                echo "simple_ondemand" > /sys/devices/gpu.0/devfreq/gpu.0/governor 2>/dev/null || true
                echo -e "${GREEN}[$(date)] ACTION${NC} - Restored GPU governor to normal mode" >> $LOG_FILE
            fi
        fi
    fi
}

# Function to check CPU usage and temperature
check_cpu() {
    # Check CPU Usage
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
    
    if [ $(echo "$CPU_USAGE > $CPU_HIGH" | bc 2>/dev/null || echo "0") -eq 1 ]; then
        echo -e "${RED}[$(date)] WARNING${NC} - CPU usage high (${CPU_USAGE}% > ${CPU_HIGH}%)" >> $LOG_FILE
        
        # Find CPU-intensive processes
        echo -e "${YELLOW}CPU-intensive processes:${NC}" >> $LOG_FILE
        ps aux --sort=-%cpu | head -5 >> $LOG_FILE
    fi
    
    # Check CPU Temperature
    if [ -f "/sys/devices/virtual/thermal/thermal_zone*/type" ]; then
        cpu_zone=$(grep -l "CPU" /sys/devices/virtual/thermal/thermal_zone*/type | head -1 | sed 's/\/type$//')
        if [ -n "$cpu_zone" ] && [ -f "${cpu_zone}/temp" ]; then
            CPU_TEMP=$(($(cat ${cpu_zone}/temp) / 1000))
            
            if [ $CPU_TEMP -gt 85 ]; then
                echo -e "${RED}[$(date)] WARNING${NC} - CPU temperature critical (${CPU_TEMP}°C > 85°C)" >> $LOG_FILE
                
                # Try to reduce CPU frequency if possible
                if [ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor" ]; then
                    echo "powersave" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || true
                    echo -e "${YELLOW}[$(date)] ACTION${NC} - Set CPU governor to powersave mode" >> $LOG_FILE
                fi
            elif [ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor" ] && [ $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor) = "powersave" ] && [ $CPU_TEMP -lt 75 ]; then
                # If temperature has dropped sufficiently, restore normal operation
                echo "ondemand" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || true
                echo -e "${GREEN}[$(date)] ACTION${NC} - Restored CPU governor to normal mode" >> $LOG_FILE
            fi
        fi
    fi
}

# Function to check for hardware accelerator usage
check_accelerators() {
    # Log DLA usage if available
    if [ -e "/dev/nvhost-nvdla0" ] || [ -e "/dev/nvhost-nvdla1" ]; then
        echo -e "${BLUE}[$(date)]${NC} DLA status: Available" >> $LOG_FILE
    fi
    
    # Log PVA usage if available
    if [ -e "/dev/nvhost-pva0" ] || [ -e "/dev/nvhost-pva1" ]; then
        echo -e "${BLUE}[$(date)]${NC} PVA status: Available" >> $LOG_FILE
    fi
    
    # Log NVENC/NVDEC usage if we can detect it
    if [ -e "/dev/nvhost-nvenc" ]; then
        echo -e "${BLUE}[$(date)]${NC} NVENC status: Available" >> $LOG_FILE
    fi
    
    if [ -e "/dev/nvhost-nvdec" ]; then
        echo -e "${BLUE}[$(date)]${NC} NVDEC status: Available" >> $LOG_FILE
    fi
}

# Function to collect and log system info every hour
collect_system_info() {
    # Current time in seconds since epoch
    current_time=$(date +%s)
    
    # Check if an hour has passed since the last collection
    if [ -z "$last_collection_time" ] || [ $((current_time - last_collection_time)) -ge 3600 ]; then
        echo -e "${BLUE}[$(date)]${NC} Collecting detailed system information..." >> $LOG_FILE
        
        # Log kernel info
        echo -e "${YELLOW}Kernel version:${NC}" >> $LOG_FILE
        uname -a >> $LOG_FILE
        
        # Log CUDA info
        if [ -f "/usr/local/cuda/bin/nvcc" ]; then
            echo -e "${YELLOW}CUDA version:${NC}" >> $LOG_FILE
            /usr/local/cuda/bin/nvcc --version | head -3 >> $LOG_FILE
        fi
        
        # Log disk usage
        echo -e "${YELLOW}Disk usage:${NC}" >> $LOG_FILE
        df -h / /advantech >> $LOG_FILE
        
        # Log memory allocation details
        echo -e "${YELLOW}Detailed memory info:${NC}" >> $LOG_FILE
        free -h >> $LOG_FILE
        
        # Update the last collection time
        last_collection_time=$current_time
    fi
}

# Main monitoring loop
echo -e "${BLUE}[$(date)]${NC} Starting resource monitoring loop" >> $LOG_FILE

# Initialize last collection time
last_collection_time=0

while true; do
    log_resources
    check_memory
    check_gpu
    check_cpu
    
    # Check accelerators every minute only
    if [ $(($(date +%s) % 60)) -eq 0 ]; then
        check_accelerators
    fi
    
    # Collect detailed system info periodically
    collect_system_info
    
    sleep $INTERVAL
done
