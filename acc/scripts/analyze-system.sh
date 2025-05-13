#!/bin/bash
# System analysis script

# Output as JSON
echo "{"

# Get Jetson model
if [ -f "/proc/device-tree/model" ]; then
    MODEL=$(cat /proc/device-tree/model | tr '\0' ' ' | xargs)
    echo "  \"jetson_model\": \"$MODEL\","
else
    echo "  \"jetson_model\": \"Unknown\","
fi

# Get JetPack version
if [ -f "/etc/nv_tegra_release" ]; then
    JETPACK=$(head -1 /etc/nv_tegra_release | sed 's/.*R\([0-9]*\) (release)/\1/g')
    echo "  \"jetpack_version\": \"$JETPACK\","
else
    echo "  \"jetpack_version\": \"Unknown\","
fi

# Get CUDA version
if command -v nvcc >/dev/null 2>&1; then
    CUDA_VERSION=$(nvcc --version | grep "release" | awk '{print $5}' | sed 's/,//')
    echo "  \"cuda_version\": \"$CUDA_VERSION\","
else
    echo "  \"cuda_version\": \"Unknown\","
fi

# Get TensorRT version
if python3 -c "import tensorrt" >/dev/null 2>&1; then
    TRT_VERSION=$(python3 -c "import tensorrt; print(tensorrt.__version__)")
    echo "  \"tensorrt_version\": \"$TRT_VERSION\","
else
    echo "  \"tensorrt_version\": \"Unknown\","
fi

# Get DeepStream version
if [ -d "/opt/nvidia/deepstream" ]; then
    DS_PATH=$(find /opt/nvidia/deepstream -maxdepth 1 -type d -name "deepstream-*" | sort -r | head -1)
    if [ -n "$DS_PATH" ]; then
        DS_VERSION=$(basename "$DS_PATH" | sed 's/deepstream-//')
        echo "  \"deepstream_version\": \"$DS_VERSION\","
    else
        echo "  \"deepstream_version\": \"Unknown\","
    fi
else
    echo "  \"deepstream_version\": \"Not installed\","
fi

# Get Python version
if command -v python3 >/dev/null 2>&1; then
    PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2)
    echo "  \"python_version\": \"$PYTHON_VERSION\","
else
    echo "  \"python_version\": \"Unknown\","
fi

# Get installed Python packages
echo "  \"python_packages\": {"
if command -v python3 >/dev/null 2>&1; then
    packages=("torch" "torchvision" "ultralytics" "opencv-python" "tensorflow" "onnx" "onnxruntime-gpu")
    for i in "${!packages[@]}"; do
        pkg="${packages[$i]}"
        pkg_name="${pkg//-/_}"
        version=$(python3 -c "
try:
    import $pkg_name
    try:
        print($pkg_name.__version__)
    except AttributeError:
        print('installed, version unknown')
except ImportError:
    print('not installed')
" 2>/dev/null || echo "error")
        
        # Add comma for all but the last item
        if [ $i -eq $((${#packages[@]} - 1)) ]; then
            echo "    \"$pkg\": \"$version\""
        else
            echo "    \"$pkg\": \"$version\","
        fi
    done
else
    echo "    \"error\": \"Python not available\""
fi
echo "  },"

# Get accelerator info
echo "  \"accelerators\": {"
accelerators=()
if [ -e "/dev/nvhost-nvdla0" ] || [ -e "/dev/nvhost-nvdla1" ]; then
    accelerators+=("\"DLA\": \"available\"")
fi
if [ -e "/dev/nvhost-pva0" ] || [ -e "/dev/nvhost-pva1" ]; then
    accelerators+=("\"PVA\": \"available\"")
fi
if [ -e "/dev/nvhost-nvenc" ]; then
    accelerators+=("\"NVENC\": \"available\"")
fi
if [ -e "/dev/nvhost-nvdec" ]; then
    accelerators+=("\"NVDEC\": \"available\"")
fi
if [ -e "/dev/nvhost-nvjpg" ]; then
    accelerators+=("\"NVJPG\": \"available\"")
fi
if [ -e "/dev/nvhost-vic" ]; then
    accelerators+=("\"VIC\": \"available\"")
fi
if [ -d "/opt/nvidia/vpi2" ]; then
    accelerators+=("\"VPI\": \"available\"")
fi
if [ -d "/usr/share/vulkan" ]; then
    accelerators+=("\"Vulkan\": \"available\"")
fi

# Join the accelerators with commas
for i in "${!accelerators[@]}"; do
    if [ $i -eq $((${#accelerators[@]} - 1)) ]; then
        echo "    ${accelerators[$i]}"
    else
        echo "    ${accelerators[$i]},"
    fi
done
echo "  },"

# Get system resources
echo "  \"resources\": {"
echo "    \"memory_total\": \"$(free -m | grep Mem | awk '{print $2}')\","
echo "    \"disk_space\": \"$(df -h / | awk 'NR==2 {print $4}')\","
echo "    \"cpu_cores\": $(nproc)
  }"

echo "}"
