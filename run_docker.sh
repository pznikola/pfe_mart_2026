#!/bin/bash
# ========================================================================
# Start script for IIC-OSIC-TOOLS with X11 GUI support
# ========================================================================

CONTAINER_NAME="iic-osic-tools_gui_uid_$(id -u)"
DOCKER_USER="hpretl"
DOCKER_IMAGE="iic-osic-tools"
DOCKER_TAG="2025.12"

# Design directory - change this to your design path
if [ -z "${DESIGNS}" ]; then
    DESIGNS="$(pwd)/exercises"
fi

# Create design directory if it doesn't exist
mkdir -p "$DESIGNS"

# Handle --reset flag
if [ "$1" = "--reset" ]; then
    echo "[INFO] Resetting container ${CONTAINER_NAME}..."
    docker stop "${CONTAINER_NAME}" 2>/dev/null
    docker rm "${CONTAINER_NAME}" 2>/dev/null
    echo "[INFO] Container removed. Creating fresh container..."
fi

# Allow local Docker connections to X server
xhost +local:docker > /dev/null 2>&1

# Check if container is already running
if [ "$(docker ps -q -f name="^${CONTAINER_NAME}$")" ]; then
    echo "[INFO] Container ${CONTAINER_NAME} is already running. Attaching..."
    docker exec -it "${CONTAINER_NAME}" /bin/bash
    exit 0
fi

# Check if container exists but is stopped
if [ "$(docker ps -aq -f name="^${CONTAINER_NAME}$")" ]; then
    echo "[INFO] Restarting existing container ${CONTAINER_NAME}..."
    docker start -ai "${CONTAINER_NAME}"
    exit 0
fi

# Create and run new container
echo "[INFO] Creating new container ${CONTAINER_NAME}..."
echo "[INFO] Design directory: ${DESIGNS}"

docker run -it \
    --name "${CONTAINER_NAME}" \
    --security-opt seccomp=unconfined \
    --net=host \
    -e DISPLAY="${DISPLAY}" \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v "${DESIGNS}":/pfe/work_area:rw \
    -w /pfe/work_area \
    "${DOCKER_USER}/${DOCKER_IMAGE}:${DOCKER_TAG}" \
    -s /bin/bash