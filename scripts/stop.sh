#!/bin/bash
# Stop script for Advantech Jetson AI container

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
EXIT_STOP_FAILED=4
EXIT_INVALID_ARGS=5

# Script variables
FORCE=0
VERBOSE=0
ACC_DIR="acc"
CONTAINER_NAME="advantech-jetson-ai"

# Set working directory to project root
cd "$(dirname "$0")/.."

# Print usage information
usage() {
    echo -e "${BLUE}Usage:${NC} $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help                Show this help message"
    echo "  -f, --force               Force stop (kill) container"
    echo "  -v, --verbose             Enable verbose output"
    echo ""
    echo "Examples:"
    echo "  $0                        Stop container gracefully"
    echo "  $0 --force                Force stop container"
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
                FORCE=1
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
            echo -e "${YELLOW}[TIP]${NC} Please install Docker to interact with the container"
            ;;
        $EXIT_NOT_RUNNING)
            echo -e "${YELLOW}[TIP]${NC} The container is not running, nothing to stop"
            ;;
        $EXIT_STOP_FAILED)
            echo -e "${YELLOW}[TIP]${NC} Try using --force option to forcefully stop the container"
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
    
    export DOCKER_COMPOSE
    echo -e "${GREEN}[OK]${NC} Docker and Docker Compose found"
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

# Stop the container with proper error handling
stop_container() {
    echo -e "${BLUE}[INFO]${NC} Stopping container..."
    
    # Export the Docker directory
    export DOCKER_DIR=$ACC_DIR
    
    # Change to compose directory
    cd compose || handle_error $EXIT_GENERAL_ERROR "Failed to change to compose directory"
    
    if [ $FORCE -eq 1 ]; then
        echo -e "${YELLOW}[WARN]${NC} Forcing container stop (kill)..."
        
        if [ $VERBOSE -eq 1 ]; then
            docker kill $CONTAINER_NAME || handle_error $EXIT_STOP_FAILED "Failed to kill container"
        else
            docker kill $CONTAINER_NAME &>/dev/null || handle_error $EXIT_STOP_FAILED "Failed to kill container"
        fi
    else
        echo -e "${BLUE}[INFO]${NC} Gracefully stopping container..."
        
        if [ $VERBOSE -eq 1 ]; then
            $DOCKER_COMPOSE down || handle_error $EXIT_STOP_FAILED "Failed to stop container"
        else
            $DOCKER_COMPOSE down &>/dev/null || handle_error $EXIT_STOP_FAILED "Failed to stop container"
        fi
    fi
    
    # Verify container is stopped
    if docker ps --format '{{.Names}}' | grep -q "$CONTAINER_NAME"; then
        handle_error $EXIT_STOP_FAILED "Container is still running. Try using --force option."
    fi
    
    echo -e "${GREEN}[SUCCESS]${NC} Container stopped successfully"
    return $EXIT_SUCCESS
}

# Main function
main() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}     Stopping Advantech Jetson AI Container          ${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Run steps with error handling
    check_docker
    check_container
    stop_container
    
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}[FINISHED]${NC} Container stopped successfully"
    echo -e "${BLUE}=====================================================${NC}"
    
    return $EXIT_SUCCESS
}

# Execute main function
main "$@"
exit $?
