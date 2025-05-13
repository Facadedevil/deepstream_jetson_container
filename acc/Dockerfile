# Use the pre-built Advantech image with AI packages
FROM harbor.arfa.wise-paas.com/advantech-coe-l2-02/advantech_coe_l2-02:v2

# Set environment variables for DeepStream
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    TZ=UTC \
    # Add DeepStream paths to existing environment - these will be updated at runtime
    LD_LIBRARY_PATH=/opt/nvidia/deepstream/lib:/opt/nvidia/deepstream/lib/gst-plugins:${LD_LIBRARY_PATH} \
    PATH=/opt/nvidia/deepstream/bin:${PATH} \
    GST_PLUGIN_PATH=/opt/nvidia/deepstream/lib/gst-plugins/:/usr/lib/aarch64-linux-gnu/gstreamer-1.0/:${GST_PLUGIN_PATH} \
    # Add DeepStream Python bindings path - will be updated by entrypoint
    PYTHONPATH=/advantech:/opt/nvidia/deepstream/deepstream-6.1/sources/deepstream_python_apps:/opt/nvidia/deepstream/deepstream-6.1/sources/deepstream_python_apps/bindings:${PYTHONPATH} \
    # Enable memory management features
    ENABLE_DYNAMIC_MEMORY=true \
    MIN_MEMORY_MB=1024 \
    MAX_MEMORY_PERCENT=75 \
    ENABLE_AUTO_SWAP=true \
    SWAP_SIZE_MB=4096 \
    GPU_MEMORY_FRACTION=0.7 \
    ENABLE_RESOURCE_MONITORING=true \
    RESOURCE_MONITOR_INTERVAL=30

# Create work directory with proper permissions
RUN mkdir -p /advantech && chmod 777 /advantech

# Copy the enhanced entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Copy utility scripts
COPY scripts/analyze-system.sh /usr/local/bin/analyze-system
COPY scripts/ds-utils.sh /usr/local/bin/ds-utils
COPY scripts/gpu-monitor.sh /usr/local/bin/gpu-monitor
COPY scripts/resource-manager.sh /usr/local/bin/resource-manager
RUN chmod +x /usr/local/bin/analyze-system \
    /usr/local/bin/ds-utils \
    /usr/local/bin/gpu-monitor \
    /usr/local/bin/resource-manager
    
# Set working directory
WORKDIR /advantech

# Use dynamic entrypoint script
ENTRYPOINT ["/entrypoint.sh"]

# Default command keeps container running
CMD ["bash", "-c", "tail -f /dev/null"]
