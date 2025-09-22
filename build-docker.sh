#!/bin/bash

# Simple Docker build and run script for wolfProvider

# Build the Docker image
echo "Building Docker image..."
docker build --build-arg HOST_UID=$(id -u) --build-arg HOST_GID=$(id -g) -t wolfprovider .

# Remove existing container if it exists
echo "Removing existing container..."
docker rm wolfprovider-net-snmp 2>/dev/null || true

# Run the container
echo "Starting container..."
docker run -it \
  -v $(pwd):/home/user/wolfProvider \
  --name wolfprovider-net-snmp \
  wolfprovider /bin/bash
