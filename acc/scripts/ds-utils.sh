#!/bin/bash
# DeepStream utility functions

# Terminal colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Find DeepStream installation
find_deepstream() {
    DS_PATHS=(
        "/opt/nvidia/deepstream/deepstream-6.2"
        "/opt/nvidia/deepstream/deepstream-6.3"
        "/opt/nvidia/deepstream/deepstream-6.1"
        "/opt/nvidia/deepstream/deepstream-6.0"
    )
    
    for path in "${DS_PATHS[@]}"; do
        if [ -d "$path/lib" ] && [ -d "$path/bin" ]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

# Print DeepStream configuration
print_ds_config() {
    DS_PATH=$(find_deepstream)
    if [ -z "$DS_PATH" ]; then
        echo -e "${RED}[ERROR]${NC} DeepStream installation not found"
        return 1
    fi
    
    echo -e "${BLUE}DeepStream Configuration${NC}"
    echo -e "${GREEN}Path:${NC} $DS_PATH"
    
    if [ -f "$DS_PATH/version" ]; then
        echo -e "${GREEN}Version:${NC} $(cat $DS_PATH/version)"
    else
        echo -e "${GREEN}Version:${NC} Unknown"
    fi
    
    echo -e "${GREEN}Libraries:${NC} $(find $DS_PATH/lib -name "*.so*" | wc -l) files"
    echo -e "${GREEN}Binaries:${NC} $(find $DS_PATH/bin -type f -executable | wc -l) files"
    echo -e "${GREEN}GStreamer plugins:${NC} $(find $DS_PATH/lib/gst-plugins -name "*.so*" 2>/dev/null | wc -l) files"
    
    return 0
}

# Check if DeepStream can run properly
check_ds_runnable() {
    DS_PATH=$(find_deepstream)
    if [ -z "$DS_PATH" ]; then
        echo -e "${RED}[ERROR]${NC} DeepStream installation not found"
        return 1
    fi
    
    # Check for critical libraries
    missing_libs=()
    critical_libs=(
        "libnvdsgst_meta.so"
        "libnvds_meta.so"
        "libnvbufsurface.so"
        "libnvbufsurftransform.so"
        "libnvdsgst_helper.so"
        "libnvds_batch_jpegenc.so"
        "libnvds_nvmultiobjecttracker.so"
    )
    
    for lib in "${critical_libs[@]}"; do
        if ! ldconfig -p | grep -q "$lib"; then
            missing_libs+=("$lib")
        fi
    done
    
    if [ ${#missing_libs[@]} -gt 0 ]; then
        echo -e "${YELLOW}[WARN]${NC} Missing libraries in system path:"
        for lib in "${missing_libs[@]}"; do
            echo -e "  - $lib"
        done
        return 1
    fi
    
    # Check for deepstream-app
    if ! command -v deepstream-app >/dev/null 2>&1; then
        echo -e "${YELLOW}[WARN]${NC} deepstream-app not found in PATH"
        return 1
    fi
    
    echo -e "${GREEN}[OK]${NC} DeepStream appears to be runnable"
    return 0
}

# If the script is executed directly, show DeepStream info
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    print_ds_config
    check_ds_runnable
fi
