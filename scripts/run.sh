#!/bin/bash
# Enhanced Run script for Advantech Jetson AI container

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
EXIT_X11_ERROR=3
EXIT_START_FAILED=4
EXIT_INVALID_ARGS=5

# Script variables
DETACHED=0
RUNTIME="nvidia"
DEVICE_LIMITS=""
MEMORY_LIMIT=""
CPU_LIMIT=""
GPU_LIMIT=""
VERBOSE=0
ACC_DIR="acc"
PROJECT_NAME="advantech-l1-05"
CONTAINER_NAME="advantech-jetson-ai"

# Set working directory to project root
cd "$(dirname "$0")/.."

# Print usage information
usage() {
    echo -e "${BLUE}Usage:${NC} $0 [options] [command]"
    echo ""
    echo "Options:"
    echo "  -h, --help                 Show this help message"
    echo "  -d, --detach               Run container in background"
    echo "  -m, --memory LIMIT         Set memory limit (e.g. 4g)"
    echo "  -c, --cpu LIMIT            Set CPU limit (e.g. 2)"
    echo "  -v, --verbose              Enable verbose output"
    echo ""
    echo "Commands:"
    echo "  If a command is provided, it will be executed inside the container"
    echo "  If no command is provided, the container will start with the default entrypoint"
    echo ""
    echo "Examples:"
    echo "  $0 --detach                Start container in background"
    echo "  $0 --memory 4g             Start container with 4GB memory limit"
    echo "  $0 system-info             Run system-info command in container"
}

# Parse command line arguments
parse_args() {
    COMMAND_ARGS=()
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--detach)
                DETACHED=1
                shift
                ;;
            -m|--memory)
                MEMORY_LIMIT="$2"
                shift 2
                ;;
            -c|--cpu)
                CPU_LIMIT="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -*)
                echo -e "${RED}Error:${NC} Unknown option: $1"
                usage
                exit $EXIT_INVALID_ARGS
                ;;
            *)
                # Collect remaining args as command
                COMMAND_ARGS+=("$1")
                shift
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
            echo -e "${YELLOW}[TIP]${NC} Please install Docker and Docker Compose"
            ;;
        $EXIT_X11_ERROR)
            echo -e "${YELLOW}[TIP]${NC} Try running 'xhost +local:docker' manually"
            ;;
        $EXIT_START_FAILED)
            echo -e "${YELLOW}[TIP]${NC} Check the docker logs with 'docker logs $CONTAINER_NAME'"
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

# Enhanced X11 setup with better error handling
setup_x11() {
    echo -e "${BLUE}[INFO]${NC} Setting up X11 for GUI applications..."
    
    # Check if X server is running
    if [ -z "$DISPLAY" ]; then
        echo -e "${YELLOW}[WARN]${NC} DISPLAY environment variable not set. GUI applications may not work."
        export DISPLAY=:0
    fi
    
    # Allow local connections to X server
    if command -v xhost >/dev/null 2>&1; then
        if ! xhost +local:docker &>/dev/null; then
            echo -e "${YELLOW}[WARN]${NC} Failed to run xhost command. GUI applications may not work."
        else
            echo -e "${GREEN}[OK]${NC} X11 permissions set for Docker"
        fi
    else
        echo -e "${YELLOW}[WARN]${NC} xhost command not found. GUI applications may not work."
    fi
    
    # Create auth file if needed
    if [ ! -f "/tmp/.docker.xauth" ]; then
        touch /tmp/.docker.xauth 2>/dev/null || {
            echo -e "${YELLOW}[WARN]${NC} Failed to create .docker.xauth file. GUI applications may not work."
            return 0
        }
        
        if command -v xauth >/dev/null 2>&1; then
            xauth nlist $DISPLAY | sed -e 's/^..../ffff/' | xauth -f /tmp/.docker.xauth nmerge - 2>/dev/null || {
                echo -e "${YELLOW}[WARN]${NC} Failed to set up X11 authentication. GUI applications may not work."
            }
        else
            echo -e "${YELLOW}[WARN]${NC} xauth command not found. GUI applications may not work."
        fi
        
        chmod 777 /tmp/.docker.xauth 2>/dev/null || {
            echo -e "${YELLOW}[WARN]${NC} Failed to set permissions on .docker.xauth file."
        }
    fi
    
    echo -e "${GREEN}[OK]${NC} X11 setup completed"
    return $EXIT_SUCCESS
}

# Check Docker installation with support for both docker-compose and docker compose
check_docker() {
    echo -e "${BLUE}[INFO]${NC} Checking Docker installation..."
    
    if ! command -v docker >/dev/null 2>&1; then
        handle_error $EXIT_NO_DOCKER "Docker not found"
    fi
    
    # Check if docker-compose is available
    if command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE="docker-compose"
    elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE="docker compose"
    else
        handle_error $EXIT_NO_DOCKER "Docker Compose not found"
    fi
    
    # Check if nvidia runtime is available
    if ! docker info 2>/dev/null | grep -q "Runtimes.*nvidia"; then
        echo -e "${YELLOW}[WARN]${NC} NVIDIA runtime not found in Docker, may not be able to access GPU"
    fi
    
    export DOCKER_COMPOSE
    echo -e "${GREEN}[OK]${NC} Docker and Docker Compose found"
    return $EXIT_SUCCESS
}

# Prepare environment variables for resource limits
prepare_resource_limits() {
    echo -e "${BLUE}[INFO]${NC} Preparing resource limits..."
    
    # Set environment variables for resource limits
    if [ -n "$MEMORY_LIMIT" ]; then
        export MEMORY_LIMIT
        echo -e "${BLUE}[INFO]${NC} Memory limit: $MEMORY_LIMIT"
        DEVICE_LIMITS="--memory $MEMORY_LIMIT"
    fi
    
    if [ -n "$CPU_LIMIT" ]; then
        export CPU_LIMIT
        echo -e "${BLUE}[INFO]${NC} CPU limit: $CPU_LIMIT"
        DEVICE_LIMITS="$DEVICE_LIMITS --cpus $CPU_LIMIT"
    fi
    
    return $EXIT_SUCCESS
}

# Configure hardware accelerators for the container
configure_accelerators() {
    echo -e "${BLUE}[INFO]${NC} Configuring hardware accelerators..."
    
    # Check for NVIDIA devices
    if ! ls /dev/nvidia* &>/dev/null; then
        echo -e "${YELLOW}[WARN]${NC} NVIDIA devices not found, GPU acceleration may not work"
    else
        echo -e "${GREEN}[OK]${NC} NVIDIA devices detected"
    fi
    
    # Check for accelerator devices and log them
    accelerators=()
    
    # Check DLA
    if [ -e "/dev/nvhost-nvdla0" ] || [ -e "/dev/nvhost-nvdla1" ]; then
        accelerators+=("DLA")
    fi
    
    # Check PVA
    if [ -e "/dev/nvhost-pva0" ] || [ -e "/dev/nvhost-pva1" ]; then
        accelerators+=("PVA")
    fi
    
    # Check NVENC/NVDEC
    if [ -e "/dev/nvhost-nvenc" ]; then
        accelerators+=("NVENC")
    fi
    
    if [ -e "/dev/nvhost-nvdec" ]; then
        accelerators+=("NVDEC")
    fi
    
    # Check NVJPG
    if [ -e "/dev/nvhost-nvjpg" ]; then
        accelerators+=("NVJPG")
    fi
    
    # Check VIC
    if [ -e "/dev/nvhost-vic" ]; then
        accelerators+=("VIC")
    fi
    
    if [ ${#accelerators[@]} -gt 0 ]; then
        echo -e "${GREEN}[OK]${NC} Hardware accelerators detected: ${accelerators[*]}"
    else
        echo -e "${YELLOW}[WARN]${NC} No hardware accelerators detected"
    fi
    
    return $EXIT_SUCCESS
}

# Enhanced start function with command execution and better error handling
start_container() {
    echo -e "${BLUE}[INFO]${NC} Starting container..."
    
    # Export the Docker directory to acc
    export DOCKER_DIR=$ACC_DIR
    echo -e "${BLUE}[INFO]${NC} Using Docker directory: ${DOCKER_DIR}"
    
    # Change to compose directory
    cd compose || handle_error $EXIT_GENERAL_ERROR "Failed to change to compose directory"
    
    # Prepare resource limits
    prepare_resource_limits
    
    # Build command for container
    CMD_ARGS=""
    if [ ${#COMMAND_ARGS[@]} -gt 0 ]; then
        # Convert command args to a string
        for arg in "${COMMAND_ARGS[@]}"; do
            CMD_ARGS="$CMD_ARGS \"$arg\""
        done
        COMMAND="bash -c $CMD_ARGS"
        export CONTAINER_COMMAND="$COMMAND"
    fi
    
    # Check if we want to run detached or with a specific command
    if [ $DETACHED -eq 1 ]; then
        echo -e "${BLUE}[INFO]${NC} Starting container in detached mode..."
        
        if [ $VERBOSE -eq 1 ]; then
            $DOCKER_COMPOSE up -d $DEVICE_LIMITS || {
                handle_error $EXIT_START_FAILED "Failed to start container in detached mode"
            }
        else
            $DOCKER_COMPOSE up -d $DEVICE_LIMITS &>/dev/null || {
                handle_error $EXIT_START_FAILED "Failed to start container in detached mode"
            }
        fi
        
        # Verify container is running
        sleep 2
        if ! docker ps | grep -q "$CONTAINER_NAME"; then
            handle_error $EXIT_START_FAILED "Container failed to start properly"
        fi
        
        echo -e "${GREEN}[SUCCESS]${NC} Container started in background!"
        
        # Execute command if provided
        if [ ${#COMMAND_ARGS[@]} -gt 0 ]; then
            echo -e "${BLUE}[INFO]${NC} Executing command in container: ${COMMAND_ARGS[*]}"
            
            if [ $VERBOSE -eq 1 ]; then
                docker exec -it $CONTAINER_NAME "${COMMAND_ARGS[@]}" || {
                    handle_error $EXIT_GENERAL_ERROR "Command execution failed"
                }
            else
                docker exec -it $CONTAINER_NAME "${COMMAND_ARGS[@]}" || {
                    handle_error $EXIT_GENERAL_ERROR "Command execution failed"
                }
            fi
            
            echo -e "${GREEN}[SUCCESS]${NC} Command executed successfully!"
        fi
    else
        echo -e "${BLUE}[INFO]${NC} Starting container in interactive mode..."
        
        if [ ${#COMMAND_ARGS[@]} -gt 0 ]; then
            # Run with command
            echo -e "${BLUE}[INFO]${NC} Running command: ${COMMAND_ARGS[*]}"
            
            if [ $VERBOSE -eq 1 ]; then
                docker run --rm -it --privileged --network host \
                    --runtime nvidia \
                    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
                    -v /tmp/.docker.xauth:/tmp/.docker.xauth:rw \
                    -v "$(pwd)/../src:/advantech/src:ro" \
                    -v "$(pwd)/../models:/advantech/models:rw" \
                    -v "$(pwd)/../logs:/advantech/logs:rw" \
                    -v "$(pwd)/../custom:/advantech/custom:ro" \
                    -v "$(pwd)/../config:/advantech/config:ro" \
                    -v "$(pwd)/../packages:/advantech/packages:rw" \
                    -e "DISPLAY=${DISPLAY:-:0}" \
                    -e "XAUTHORITY=/tmp/.docker.xauth" \
                    $DEVICE_LIMITS \
                    "${PROJECT_NAME}:jetson-ai" "${COMMAND_ARGS[@]}" || {
                        handle_error $EXIT_START_FAILED "Failed to run container with command"
                    }
            else
                docker run --rm -it --privileged --network host \
                    --runtime nvidia \
                    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
                    -v /tmp/.docker.xauth:/tmp/.docker.xauth:rw \
                    -v "$(pwd)/../src:/advantech/src:ro" \
                    -v "$(pwd)/../models:/advantech/models:rw" \
                    -v "$(pwd)/../logs:/advantech/logs:rw" \
                    -v "$(pwd)/../custom:/advantech/custom:ro" \
                    -v "$(pwd)/../config:/advantech/config:ro" \
                    -v "$(pwd)/../packages:/advantech/packages:rw" \
                    -e "DISPLAY=${DISPLAY:-:0}" \
                    -e "XAUTHORITY=/tmp/.docker.xauth" \
                    $DEVICE_LIMITS \
                    "${PROJECT_NAME}:jetson-ai" "${COMMAND_ARGS[@]}" || {
                        handle_error $EXIT_START_FAILED "Failed to run container with command"
                    }
            fi
        else
            # Run without command (using default entrypoint)
            if [ $VERBOSE -eq 1 ]; then
                $DOCKER_COMPOSE up $DEVICE_LIMITS || {
                    handle_error $EXIT_START_FAILED "Failed to start container"
                }
            else
                $DOCKER_COMPOSE up $DEVICE_LIMITS || {
                    handle_error $EXIT_START_FAILED "Failed to start container"
                }
            fi
        fi
        
        echo -e "${GREEN}[SUCCESS]${NC} Container session ended!"
    fi
    
    return $EXIT_SUCCESS
}

# Main function
main() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}     Running Advantech Jetson AI Container           ${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Run steps with error handling
    check_docker
    setup_x11 || echo -e "${YELLOW}[WARN]${NC} X11 setup incomplete, GUI applications may not work"
    configure_accelerators
    start_container
    
    echo -e "${BLUE}=====================================================${NC}"
    if [ $DETACHED -eq 1 ]; then
        echo -e "${GREEN}[RUNNING]${NC} Container is running in the background"
        echo -e "${YELLOW}[TIP]${NC} Use './scripts/exec.sh' to connect to the container"
        echo -e "${YELLOW}[TIP]${NC} Use './scripts/exec.sh system-info' to see system details"
        echo -e "${YELLOW}[TIP]${NC} Use './scripts/stop.sh' to stop the container"
    else
        echo -e "${GREEN}[FINISHED]${NC} Container session has ended"
    fi
    echo -e "${BLUE}=====================================================${NC}"
    
    return $EXIT_SUCCESS
}

# Execute main function
main "$@"
exit $?
