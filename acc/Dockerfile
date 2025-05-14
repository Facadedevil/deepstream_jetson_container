FROM harbor.arfa.wise-paas.com/advantech-coe-l2-02/advantech_coe_l2-02:v2

# Set environment variables for DeepStream
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    TZ=UTC

# Create work directory with proper permissions
RUN mkdir -p /advantech && chmod 777 /advantech

# Copy the enhanced entrypoint script and make it executable
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Copy utility scripts to /usr/local/bin to make them accessible in PATH
COPY scripts/analyze-system.sh /usr/local/bin/analyze-system
COPY scripts/ds-utils.sh /usr/local/bin/ds-utils
COPY scripts/gpu-monitor.sh /usr/local/bin/gpu-monitor
COPY scripts/resource-manager.sh /usr/local/bin/resource-manager
RUN chmod +x /usr/local/bin/analyze-system \
    /usr/local/bin/ds-utils \
    /usr/local/bin/gpu-monitor \
    /usr/local/bin/resource-manager

# Create additional utility scripts for DeepStream
RUN echo '#!/bin/bash\n\
echo "Running DeepStream system check..."\n\
ds-utils\n\
echo ""\n\
echo "DeepStream environment variables:"\n\
echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"\n\
echo "GST_PLUGIN_PATH: $GST_PLUGIN_PATH"\n\
echo "PATH: $PATH"\n\
echo "PYTHONPATH: $PYTHONPATH"\n\
\n\
# Check for critical libraries\n\
echo ""\n\
echo "Checking for critical DeepStream libraries:"\n\
for lib in libnvdsgst_meta.so libnvds_meta.so libnvstreammux.so; do\n\
  found=$(find /opt/nvidia/deepstream /usr/lib/aarch64-linux-gnu -name "$lib*" 2>/dev/null | head -1)\n\
  if [ -n "$found" ]; then\n\
    echo "✓ $lib: $found"\n\
  else\n\
    echo "✗ $lib: Not found"\n\
  fi\n\
done\n\
\n\
# Check for GStreamer plugins\n\
echo ""\n\
echo "Checking DeepStream GStreamer plugins:"\n\
for plugin in nvstreammux nvinfer nvvideoconvert nvdsosd; do\n\
  if gst-inspect-1.0 $plugin &>/dev/null; then\n\
    echo "✓ $plugin plugin is available"\n\
  else\n\
    echo "✗ $plugin plugin is NOT available"\n\
  fi\n\
done\n\
' > /usr/local/bin/ds-check && chmod +x /usr/local/bin/ds-check

# Create a script for DeepStream model conversion and optimization
RUN echo '#!/bin/bash\n\
# DeepStream Model Optimizer\n\
\n\
# Terminal colors\n\
GREEN="\033[0;32m"\n\
BLUE="\033[0;34m"\n\
YELLOW="\033[0;33m"\n\
RED="\033[0;31m"\n\
NC="\033[0m" # No Color\n\
\n\
echo -e "${BLUE}DeepStream Model Optimizer${NC}"\n\
echo -e "This utility helps convert and optimize models for DeepStream"\n\
\n\
# Check if TensorRT is available\n\
if ! command -v trtexec &> /dev/null; then\n\
    echo -e "${RED}Error: TensorRT tools not found${NC}"\n\
    echo -e "Please ensure TensorRT is properly installed"\n\
    exit 1\n\
fi\n\
\n\
# Print help if no arguments provided\n\
if [ $# -eq 0 ]; then\n\
    echo -e "${YELLOW}Usage:${NC}"\n\
    echo -e "  ds-optimize [options] <input_model>"\n\
    echo -e "\n${YELLOW}Options:${NC}"\n\
    echo -e "  --fp16         Enable FP16 precision (default)"\n\
    echo -e "  --fp32         Use FP32 precision"\n\
    echo -e "  --int8         Enable INT8 precision (requires calibration)"\n\
    echo -e "  --batch N      Set batch size (default: 1)"\n\
    echo -e "  --output FILE  Specify output engine file"\n\
    echo -e "\n${YELLOW}Example:${NC}"\n\
    echo -e "  ds-optimize --fp16 --batch 1 model.onnx"\n\
    exit 0\n\
fi\n\
\n\
echo -e "${GREEN}TensorRT optimization will be implemented in a future update${NC}"\n\
' > /usr/local/bin/ds-optimize && chmod +x /usr/local/bin/ds-optimize

# Create a configuration file detector for DeepStream
RUN echo '#!/bin/bash\n\
# DeepStream Configuration Generator\n\
\n\
# Terminal colors\n\
GREEN="\033[0;32m"\n\
BLUE="\033[0;34m"\n\
YELLOW="\033[0;33m"\n\
RED="\033[0;31m"\n\
NC="\033[0m" # No Color\n\
\n\
echo -e "${BLUE}DeepStream Configuration Generator${NC}"\n\
\n\
# Print help if no arguments or --help provided\n\
if [ $# -eq 0 ] || [ "$1" == "--help" ]; then\n\
    echo -e "${YELLOW}Usage:${NC}"\n\
    echo -e "  ds-config [options] <output_file>"\n\
    echo -e "\n${YELLOW}Options:${NC}"\n\
    echo -e "  --type TYPE    Config type: detector, classifier, app (default: app)"\n\
    echo -e "  --source SRC   Source type: file, rtsp, camera (default: file)"\n\
    echo -e "  --model PATH   Path to model file"\n\
    echo -e "\n${YELLOW}Example:${NC}"\n\
    echo -e "  ds-config --type detector --source rtsp --model /path/to/model.onnx config.txt"\n\
    exit 0\n\
fi\n\
\n\
echo -e "${GREEN}DeepStream configuration generation will be implemented in a future update${NC}"\n\
' > /usr/local/bin/ds-config && chmod +x /usr/local/bin/ds-config

# Create a DeepStream wrapper script for easier execution
RUN echo '#!/bin/bash\n\
# DeepStream Application Runner\n\
\n\
# Define path to DeepStream\n\
if [ -d "/opt/nvidia/deepstream/deepstream-6.3" ]; then\n\
    DS_PATH="/opt/nvidia/deepstream/deepstream-6.3"\n\
    DS_VERSION="6.3"\n\
elif [ -d "/opt/nvidia/deepstream/deepstream-6.2" ]; then\n\
    DS_PATH="/opt/nvidia/deepstream/deepstream-6.2"\n\
    DS_VERSION="6.2"\n\
elif [ -d "/opt/nvidia/deepstream/deepstream-6.1" ]; then\n\
    DS_PATH="/opt/nvidia/deepstream/deepstream-6.1"\n\
    DS_VERSION="6.1"\n\
elif [ -d "/opt/nvidia/deepstream/deepstream-6.0" ]; then\n\
    DS_PATH="/opt/nvidia/deepstream/deepstream-6.0"\n\
    DS_VERSION="6.0"\n\
elif [ -d "/opt/nvidia/deepstream" ]; then\n\
    DS_PATH="/opt/nvidia/deepstream"\n\
    DS_VERSION="unknown"\n\
else\n\
    echo "DeepStream installation not found!"\n\
    exit 1\n\
fi\n\
\n\
# Set up environment for DeepStream\n\
export LD_LIBRARY_PATH=$DS_PATH/lib:$DS_PATH/lib/gst-plugins:/usr/lib/aarch64-linux-gnu/gstreamer-1.0:$LD_LIBRARY_PATH\n\
export GST_PLUGIN_PATH=$DS_PATH/lib/gst-plugins:/usr/lib/aarch64-linux-gnu/gstreamer-1.0:$GST_PLUGIN_PATH\n\
export PATH=$DS_PATH/bin:$PATH\n\
export PYTHONPATH=$DS_PATH/sources/deepstream_python_apps:$DS_PATH/sources/deepstream_python_apps/bindings:$PYTHONPATH\n\
\n\
# Helper for memory optimization before running DeepStream\n\
if [ -f "/usr/local/bin/optimize-for-gpu" ]; then\n\
    /usr/local/bin/optimize-for-gpu > /dev/null 2>&1 || true\n\
fi\n\
\n\
# Show info about execution\n\
echo "Running DeepStream command with version $DS_VERSION: $@"\n\
\n\
# Execute the command\n\
exec "$@"\n\
' > /usr/local/bin/run-deepstream && chmod +x /usr/local/bin/run-deepstream

# Create a usage guide script
RUN echo '#!/bin/bash\n\
echo "=== Advantech Edge AI Container with DeepStream Support ==="\n\
echo ""\n\
echo "Available DeepStream utilities:"\n\
echo "  run-deepstream     - Run DeepStream applications with proper environment"\n\
echo "                       Example: run-deepstream deepstream-app -c config.txt"\n\
echo "  ds-check           - Check DeepStream installation and configuration"\n\
echo "  ds-optimize        - Optimize models for DeepStream (with TensorRT)"\n\
echo "  ds-config          - Generate DeepStream configuration files"\n\
echo "  ds-utils           - Basic DeepStream utility functions"\n\
echo ""\n\
echo "System utilities:"\n\
echo "  analyze-system     - Print detailed system information"\n\
echo "  gpu-monitor        - Monitor GPU usage"\n\
echo "  resource-manager   - Manage system resources"\n\
echo "  container-info     - Show container configuration"\n\
echo "  optimize-for-gpu   - Optimize system for GPU processing"\n\
echo ""\n\
echo "Usage examples:"\n\
echo "  ds-check                        - Check DeepStream installation"\n\
echo "  run-deepstream python app.py    - Run a Python DeepStream application"\n\
echo "  run-deepstream gst-launch-1.0 videotestsrc ! nvvideoconvert ! fakesink - Test a pipeline"\n\
echo ""\n\
echo "For more information, run any command with --help"\n\
echo "=================================================="\n\
' > /usr/local/bin/deepstream-help && chmod +x /usr/local/bin/deepstream-help

# Create a default setup script
RUN echo '#!/bin/bash\n\
echo "Setting up DeepStream environment..."\n\
\n\
# Find DeepStream installation\n\
if [ -d "/opt/nvidia/deepstream/deepstream-6.3" ]; then\n\
    DS_PATH="/opt/nvidia/deepstream/deepstream-6.3"\n\
    DS_VERSION="6.3"\n\
elif [ -d "/opt/nvidia/deepstream/deepstream-6.2" ]; then\n\
    DS_PATH="/opt/nvidia/deepstream/deepstream-6.2"\n\
    DS_VERSION="6.2"\n\
elif [ -d "/opt/nvidia/deepstream/deepstream-6.1" ]; then\n\
    DS_PATH="/opt/nvidia/deepstream/deepstream-6.1"\n\
    DS_VERSION="6.1"\n\
elif [ -d "/opt/nvidia/deepstream/deepstream-6.0" ]; then\n\
    DS_PATH="/opt/nvidia/deepstream/deepstream-6.0"\n\
    DS_VERSION="6.0"\n\
elif [ -d "/opt/nvidia/deepstream" ]; then\n\
    DS_PATH="/opt/nvidia/deepstream"\n\
    DS_VERSION="unknown"\n\
else\n\
    echo "DeepStream installation not found!"\n\
    exit 1\n\
fi\n\
\n\
# Update environment variables in system profile\n\
cat > /etc/profile.d/deepstream.sh << EOF\n\
# DeepStream environment setup\n\
export DS_VERSION="$DS_VERSION"\n\
export DS_PATH="$DS_PATH"\n\
export LD_LIBRARY_PATH=\$DS_PATH/lib:\$DS_PATH/lib/gst-plugins:\$LD_LIBRARY_PATH\n\
export PATH=\$DS_PATH/bin:\$PATH\n\
export GST_PLUGIN_PATH=\$DS_PATH/lib/gst-plugins:/usr/lib/aarch64-linux-gnu/gstreamer-1.0:\$GST_PLUGIN_PATH\n\
export PYTHONPATH=\$DS_PATH/sources/deepstream_python_apps:\$DS_PATH/sources/deepstream_python_apps/bindings:\$PYTHONPATH\n\
EOF\n\
\n\
chmod +x /etc/profile.d/deepstream.sh\n\
echo "DeepStream $DS_VERSION environment configured"\n\
' > /usr/local/bin/setup-deepstream && chmod +x /usr/local/bin/setup-deepstream

# Set the working directory
WORKDIR /advantech

# Use the entrypoint script
ENTRYPOINT ["/entrypoint.sh"]

# Default command keeps container running
CMD ["bash", "-c", "tail -f /dev/null"]