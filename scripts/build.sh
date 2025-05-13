#!/bin/bash
# Build script for Advantech Jetson AI container using existing docker-compose.yml

# Terminal colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Exit codes
EXIT_SUCCESS=0
EXIT_GENERAL_ERROR=1
EXIT_NO_DOCKER=2
EXIT_BUILD_FAILED=3
EXIT_INVALID_ARGS=4
EXIT_COMPOSE_MISSING=5

# Script variables
FORCE_REBUILD=0
NO_CACHE=0
VERBOSE=0
PROJECT_NAME="advantech-l1-05"
COMPOSE_DIR="compose"

# Set working directory to project root
cd "$(dirname "$0")/.."
ROOT_DIR=$(pwd)

# Print usage information
usage() {
    echo -e "${BLUE}Usage:${NC} $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help                Show this help message"
    echo "  -f, --force               Force rebuild even if container exists"
    echo "  -n, --no-cache            Build without using cache"
    echo "  -v, --verbose             Enable verbose output"
    echo ""
    echo "Examples:"
    echo "  $0 --force                Force rebuild"
    echo "  $0 --no-cache             Build without using cache"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -f|--force)
                FORCE_REBUILD=1
                shift
                ;;
            -n|--no-cache)
                NO_CACHE=1
                shift
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            *)
                echo -e "${RED}Error:${NC} Unknown option: $1"
                usage
                exit $EXIT_INVALID_ARGS
                ;;
        esac
    done
}

# Error handling function
handle_error() {
    local exit_code=$1
    local error_message=$2
    
    echo -e "${RED}[ERROR]${NC} ${error_message}"
    
    # Take action based on the error
    case $exit_code in
        $EXIT_NO_DOCKER)
            echo -e "${YELLOW}[TIP]${NC} Please install Docker and Docker Compose to build the container"
            ;;
        $EXIT_BUILD_FAILED)
            echo -e "${YELLOW}[TIP]${NC} Check the build logs for more information"
            ;;
        $EXIT_COMPOSE_MISSING)
            echo -e "${YELLOW}[TIP]${NC} Please make sure docker-compose.yml exists in the ${COMPOSE_DIR} directory"
            ;;
        $EXIT_INVALID_ARGS)
            echo -e "${YELLOW}[TIP]${NC} See usage information above"
            ;;
        *)
            echo -e "${YELLOW}[TIP]${NC} See error message above"
            ;;
    esac
    
    exit $exit_code
}

# Detect Jetson device
detect_jetson() {
    echo -e "${BLUE}[INFO]${NC} Detecting Jetson device..."
    
    if [ -f "/proc/device-tree/model" ]; then
        JETSON_MODEL=$(cat /proc/device-tree/model | tr '\0' ' ' | xargs)
        echo -e "${GREEN}[FOUND]${NC} Jetson device: ${JETSON_MODEL}"
        
        # Set CUDA architecture based on model
        if echo "$JETSON_MODEL" | grep -q "Orin"; then
            export CUDA_ARCH_BIN="8.7"
            echo -e "${GREEN}[INFO]${NC} Setting CUDA architecture to ${CUDA_ARCH_BIN} for Orin"
        elif echo "$JETSON_MODEL" | grep -q "Xavier"; then
            export CUDA_ARCH_BIN="7.2"
            echo -e "${GREEN}[INFO]${NC} Setting CUDA architecture to ${CUDA_ARCH_BIN} for Xavier"
        elif echo "$JETSON_MODEL" | grep -q "Nano"; then
            export CUDA_ARCH_BIN="5.3"
            echo -e "${GREEN}[INFO]${NC} Setting CUDA architecture to ${CUDA_ARCH_BIN} for Nano"
        elif echo "$JETSON_MODEL" | grep -q "TX"; then
            export CUDA_ARCH_BIN="6.2"
            echo -e "${GREEN}[INFO]${NC} Setting CUDA architecture to ${CUDA_ARCH_BIN} for TX2"
        else
            export CUDA_ARCH_BIN="7.2"
            echo -e "${YELLOW}[WARN]${NC} Unknown Jetson model, using default CUDA architecture ${CUDA_ARCH_BIN}"
        fi
        
        return $EXIT_SUCCESS
    else
        echo -e "${YELLOW}[WARN]${NC} Not running on a Jetson device or unable to detect model"
        echo -e "${YELLOW}[INFO]${NC} Using default CUDA architecture 7.2"
        export JETSON_MODEL="Unknown"
        export CUDA_ARCH_BIN="7.2"
        
        return $EXIT_GENERAL_ERROR
    fi
}

# Create necessary directories
create_directories() {
    echo -e "${BLUE}[INFO]${NC} Creating required directories..."
    
    # Create directories if they don't exist
    for dir in models/deepstream models/yolo models/tensorflow models/tflite models/onnx logs config/deepstream config/yolo src/deepstream src/yolo src/tensorflow custom packages; do
        if [ ! -d "$dir" ]; then
            echo -e "${BLUE}[INFO]${NC} Creating directory: $dir"
            mkdir -p "$dir" || {
                handle_error $EXIT_GENERAL_ERROR "Failed to create directory: $dir"
                return $EXIT_GENERAL_ERROR
            }
        fi
    done
    
    # Verify directories are writable and set proper permissions
    for dir in models logs packages; do
        echo -e "${BLUE}[INFO]${NC} Setting permissions for: $dir"
        if ! chmod -R 777 "$dir" 2>/dev/null; then
            echo -e "${YELLOW}[WARN]${NC} Failed to set permissions on $dir, trying with sudo..."
            sudo chmod -R 777 "$dir" 2>/dev/null || {
                echo -e "${YELLOW}[WARN]${NC} Failed to set permissions on directory: $dir"
                echo -e "${YELLOW}[WARN]${NC} You may need to manually set permissions after the build"
            }
        fi
        
        if ! touch "$dir/.test_write" &>/dev/null; then
            echo -e "${YELLOW}[WARN]${NC} Directory not writable: $dir"
            echo -e "${YELLOW}[WARN]${NC} You may need to manually set permissions after the build"
        else
            rm -f "$dir/.test_write" &>/dev/null
        fi
    done
    
    echo -e "${GREEN}[OK]${NC} Directories created with proper permissions"
    return $EXIT_SUCCESS
}

# Check Docker installation
check_docker() {
    echo -e "${BLUE}[INFO]${NC} Checking Docker installation..."
    
    if ! command -v docker >/dev/null 2>&1; then
        handle_error $EXIT_NO_DOCKER "Docker not found"
    fi
    
    # Check docker-compose command
    if command -v docker-compose >/dev/null 2>&1; then
        DC="docker-compose"
        echo -e "${GREEN}[OK]${NC} Using docker-compose command"
    elif docker compose version >/dev/null 2>&1; then
        DC="docker compose"
        echo -e "${GREEN}[OK]${NC} Using 'docker compose' command"
    else
        handle_error $EXIT_NO_DOCKER "Docker Compose not found. Please install Docker Compose."
    fi
    
    return $EXIT_SUCCESS
}

# Check if docker-compose.yml exists
check_compose_file() {
    echo -e "${BLUE}[INFO]${NC} Checking for docker-compose.yml file..."
    
    if [ ! -f "${COMPOSE_DIR}/docker-compose.yml" ]; then
        handle_error $EXIT_COMPOSE_MISSING "docker-compose.yml not found in ${COMPOSE_DIR} directory"
    fi
    
    echo -e "${GREEN}[OK]${NC} docker-compose.yml found"
    return $EXIT_SUCCESS
}

# Check if container already exists
check_existing_container() {
    echo -e "${BLUE}[INFO]${NC} Checking for existing container image..."
    
    # Check if image already exists
    if docker image inspect "${PROJECT_NAME}:jetson-ai" &>/dev/null; then
        if [ $FORCE_REBUILD -eq 0 ]; then
            echo -e "${YELLOW}[WARN]${NC} Container image already exists. Use --force to rebuild."
            read -p "Rebuild anyway? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo -e "${GREEN}[INFO]${NC} Using existing container image."
                return 1  # Skip build
            fi
        else
            echo -e "${BLUE}[INFO]${NC} Force rebuild enabled, rebuilding existing image."
        fi
    else
        echo -e "${BLUE}[INFO]${NC} No existing container image found, building new image."
    fi
    
    return 0  # Continue with build
}

# Build the container using existing docker-compose.yml
build_container() {
    echo -e "${BLUE}[INFO]${NC} Building container using docker-compose..."
    
    # Change to the compose directory
    cd "${COMPOSE_DIR}" || handle_error $EXIT_GENERAL_ERROR "Failed to change to ${COMPOSE_DIR} directory"
    
    # Set environment variables for the build
    export CUDA_ARCH_BIN
    
    # Set build options
    BUILD_OPTS=""
    if [ $NO_CACHE -eq 1 ]; then
        BUILD_OPTS="--no-cache"
    fi
    
    # Build output handling
    BUILD_LOG="${ROOT_DIR}/logs/build_$(date +%Y%m%d_%H%M%S).log"
    
    # Create logs directory if it doesn't exist
    mkdir -p "${ROOT_DIR}/logs"
    
    if [ $VERBOSE -eq 1 ]; then
        # Show output in real-time for verbose mode
        echo -e "${BLUE}[INFO]${NC} Building image with verbose output: ${PROJECT_NAME}:jetson-ai"
        
        $DC build $BUILD_OPTS || {
            handle_error $EXIT_BUILD_FAILED "Container build failed"
        }
    else
        # Show a simple progress indicator and save log
        echo -e "${BLUE}[INFO]${NC} Building image: ${PROJECT_NAME}:jetson-ai"
        echo -e "${BLUE}[INFO]${NC} Build log will be saved to: $BUILD_LOG"
        
        # Show a simple progress indicator
        $DC build $BUILD_OPTS > $BUILD_LOG 2>&1 &
        build_pid=$!
        
        echo -n "Building: "
        while kill -0 $build_pid 2>/dev/null; do
            echo -n "."
            sleep 2
        done
        echo ""
        
        # Check if build was successful
        wait $build_pid
        if [ $? -ne 0 ]; then
            echo -e "${RED}[ERROR]${NC} Container build failed!"
            echo -e "${YELLOW}[INFO]${NC} Last 20 lines of build log:"
            tail -n 20 "$BUILD_LOG"
            handle_error $EXIT_BUILD_FAILED "Container build failed"
        fi
    fi
    
    # Return to the original directory
    cd "${ROOT_DIR}"
    
    echo -e "${GREEN}[SUCCESS]${NC} Container built successfully!"
    return $EXIT_SUCCESS
}

# Main function
main() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}     Building Advantech Jetson AI Container          ${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Run steps with error handling
    check_docker
    check_compose_file  
    detect_jetson
    create_directories
    
    # Check for existing container
    if check_existing_container; then
        # Only build if needed
        build_container
    fi
    
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}[FINISHED]${NC} Container setup completed!"
    echo -e "${YELLOW}[TIP]${NC} Run './scripts/run.sh' to start the container"
    echo -e "${YELLOW}[TIP]${NC} Run './scripts/exec.sh' to execute commands in the running container"
    echo -e "${BLUE}=====================================================${NC}"
    
    return $EXIT_SUCCESS
}

# Execute main function
main "$@"
exit $?
