#!/bin/bash
# GPU monitoring script for Jetson devices

# Set default values
INTERVAL=${INTERVAL:-2}  # Check every 2 seconds
LOG_FILE="/advantech/logs/gpu-usage.log"

# Create log directory if it doesn't exist
mkdir -p $(dirname $LOG_FILE)

# Log start
echo "$(date): GPU Monitor started" > $LOG_FILE

# Function to get GPU usage for Jetson
get_jetson_gpu_usage() {
    if [ -f "/sys/devices/gpu.0/load" ]; then
        cat /sys/devices/gpu.0/load
    else
        echo "N/A"
    fi
}

# Function to get GPU frequency
get_gpu_freq() {
    if [ -f "/sys/devices/gpu.0/devfreq/gpu.0/cur_freq" ]; then
        echo $(($(cat /sys/devices/gpu.0/devfreq/gpu.0/cur_freq) / 1000000))
    else
        echo "N/A"
    fi
}

# Function to get GPU temperature
get_gpu_temp() {
    if [ -f "/sys/devices/virtual/thermal/thermal_zone*/type" ]; then
        # Find the GPU thermal zone
        gpu_zone=$(grep -l "GPU" /sys/devices/virtual/thermal/thermal_zone*/type | head -1 | sed 's/\/type$//')
        if [ -n "$gpu_zone" ] && [ -f "${gpu_zone}/temp" ]; then
            echo $(($(cat ${gpu_zone}/temp) / 1000))
        else
            echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

# Function to log GPU information
log_gpu_info() {
    GPU_USAGE=$(get_jetson_gpu_usage)
    GPU_FREQ=$(get_gpu_freq)
    GPU_TEMP=$(get_gpu_temp)
    
    echo "$(date): GPU Usage=${GPU_USAGE}%, Freq=${GPU_FREQ}MHz, Temp=${GPU_TEMP}°C" >> $LOG_FILE
}

# Main monitoring loop
echo "$(date): Starting GPU monitoring" >> $LOG_FILE
while true; do
    log_gpu_info
    sleep $INTERVAL
done
