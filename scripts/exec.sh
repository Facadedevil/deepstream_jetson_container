#!/bin/bash
# Enhanced Execute script for the Advantech Jetson AI container

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
EXIT_NOT_RUNNING=3
EXIT_EXEC_FAILED=4
EXIT_INVALID_ARGS=5

# Script variables
CONTAINER_NAME="advantech-jetson-ai"
INTERACTIVE=1
VERBOSE=0
WRAPPER=""
ROOT=0
ENV_VARS=()

# Set working directory to project root
cd "$(dirname "$0")/.."

# Print usage information
usage() {
    echo -e "${BLUE}Usage:${NC} $0 [options] [command]"
    echo ""
    echo "Options:"
    echo "  -h, --help                 Show this help message"
    echo "  -d, --detach               Run in non-interactive mode"
    echo "  -v, --verbose              Enable verbose output"
    echo "  -r, --root                 Run command as root"
    echo "  -e, --env KEY=VALUE        Set environment variable"
    echo "  -y, --yolo                 Use YOLO wrapper"
    echo "  -t, --tensorflow, --tf     Use TensorFlow wrapper"
    echo "  -ds, --deepstream          Use DeepStream wrapper"
    echo ""
    echo "Commands:"
    echo "  If no command is provided, an interactive shell will be started"
    echo ""
    echo "Examples:"
    echo "  $0                         Start interactive shell"
    echo "  $0 system-info             Run system-info command"
    echo "  $0 --yolo python app.py    Run Python script with YOLO wrapper"
    echo "  $0 --tensorflow python model.py   Run Python script with TensorFlow wrapper"
    echo "  $0 --env BATCH_SIZE=64 python train.py   Run with environment variable"
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
                INTERACTIVE=0
                shift
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -r|--root)
                ROOT=1
                shift
                ;;
            -e|--env)
                if [[ "$2" == *"="* ]]; then
                    ENV_VARS+=("$2")
                    shift 2
                else
                    echo -e "${RED}Error:${NC} Environment variable must be in format KEY=VALUE"
                    usage
                    exit $EXIT_INVALID_ARGS
                fi
                ;;
            -y|--yolo)
                WRAPPER="run-yolo"
                shift
                ;;
            -t|--tensorflow|--tf)
                WRAPPER="run-tf"
                shift
                ;;
            -ds|--deepstream)
                WRAPPER="run-deepstream"
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
            echo -e "${YELLOW}[TIP]${NC} Please install Docker to interact with the container"
            ;;
        $EXIT_NOT_RUNNING)
            echo -e "${YELLOW}[TIP]${NC} Start the container first with './scripts/run.sh'"
            echo -e "${YELLOW}[TIP]${NC} Or run it in the background with './scripts/run.sh --detach'"
            ;;
        $EXIT_EXEC_FAILED)
            echo -e "${YELLOW}[TIP]${NC} Check if the container is running properly with 'docker ps'"
            echo -e "${YELLOW}[TIP]${NC} Check logs with 'docker logs $CONTAINER_NAME'"
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

# Check Docker installation
check_docker() {
    echo -e "${BLUE}[INFO]${NC} Checking Docker installation..."
    
    if ! command -v docker >/dev/null 2>&1; then
        handle_error $EXIT_NO_DOCKER "Docker not found"
    fi
    
    echo -e "${GREEN}[OK]${NC} Docker found"
    return $EXIT_SUCCESS
}

# Check if container is running
check_container() {
    echo -e "${BLUE}[INFO]${NC} Checking if container is running..."
    
    if ! docker ps --format '{{.Names}}' | grep -q "$CONTAINER_NAME"; then
        handle_error $EXIT_NOT_RUNNING "Container '$CONTAINER_NAME' is not running"
    fi
    
    echo -e "${GREEN}[OK]${NC} Container is running"
    return $EXIT_SUCCESS
}

# Execute command in container with error handling
exec_in_container() {
    # Prepare Docker exec command with appropriate options
    EXEC_CMD="docker exec"
    
    # Add environment variables
    for env_var in "${ENV_VARS[@]}"; do
        EXEC_CMD="$EXEC_CMD -e $env_var"
    done
    
    # Add interactive flag if needed
    if [ $INTERACTIVE -eq 1 ]; then
        EXEC_CMD="$EXEC_CMD -it"
    fi
    
    # Add user flag if needed
    if [ $ROOT -eq 1 ]; then
        EXEC_CMD="$EXEC_CMD -u root"
    fi
    
    # Add container name
    EXEC_CMD="$EXEC_CMD $CONTAINER_NAME"
    
    # Add wrapper if specified
    if [ -n "$WRAPPER" ]; then
        EXEC_CMD="$EXEC_CMD $WRAPPER"
    fi
    
    # Execute command or start shell
    if [ ${#COMMAND_ARGS[@]} -eq 0 ]; then
        echo -e "${BLUE}[INFO]${NC} Starting interactive shell in container..."
        
        if [ $VERBOSE -eq 1 ]; then
            echo -e "${BLUE}[CMD]${NC} $EXEC_CMD bash"
        fi
        
        if ! $EXEC_CMD bash; then
            handle_error $EXIT_EXEC_FAILED "Failed to start shell in container"
        fi
    else
        echo -e "${BLUE}[INFO]${NC} Executing command in container: ${COMMAND_ARGS[*]}"
        
        if [ $VERBOSE -eq 1 ]; then
            echo -e "${BLUE}[CMD]${NC} $EXEC_CMD ${COMMAND_ARGS[*]}"
        fi
        
        if ! $EXEC_CMD "${COMMAND_ARGS[@]}"; then
            handle_error $EXIT_EXEC_FAILED "Command failed in container"
        fi
    fi
    
    return $EXIT_SUCCESS
}

# Check for common commands and suggest wrappers
suggest_wrapper() {
    if [ -z "$WRAPPER" ] && [ ${#COMMAND_ARGS[@]} -gt 0 ]; then
        # Check for Python commands that might benefit from wrappers
        if [ "${COMMAND_ARGS[0]}" == "python" ] || [ "${COMMAND_ARGS[0]}" == "python3" ]; then
            # Check filename for clues
            if [ ${#COMMAND_ARGS[@]} -gt 1 ]; then
                filename="${COMMAND_ARGS[1]}"
                if [[ "$filename" == *"yolo"* ]] || [[ "$filename" == *"detect"* ]] || [[ "$filename" == *"ultra"* ]]; then
                    echo -e "${YELLOW}[TIP]${NC} This looks like a YOLO script. Consider using --yolo for better performance."
                elif [[ "$filename" == *"tensorflow"* ]] || [[ "$filename" == *"tf_"* ]] || [[ "$filename" == *"keras"* ]]; then
                    echo -e "${YELLOW}[TIP]${NC} This looks like a TensorFlow script. Consider using --tensorflow for better performance."
                elif [[ "$filename" == *"deepstream"* ]] || [[ "$filename" == *"ds_"* ]]; then
                    echo -e "${YELLOW}[TIP]${NC} This looks like a DeepStream script. Consider using --deepstream for better performance."
                fi
            fi
        fi
    fi
}

# Main function
main() {
    echo -e "${BLUE}[INFO]${NC} Accessing Advantech Jetson AI container..."
    
    # Parse command line arguments
    parse_args "$@"
    
    # Run steps with error handling
    check_docker
    check_container
    suggest_wrapper
    exec_in_container
    
    echo -e "${GREEN}[DONE]${NC} Command completed successfully"
    return $EXIT_SUCCESS
}

# Execute main function
main "$@"
exit $?
