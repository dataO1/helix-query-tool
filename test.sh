#!/bin/bash
set -e

echo "=== Building container runtime ==="
nix build .#helixdb-runtime
echo "✓ Runtime built"

echo -e "\n=== Building Docker image ==="
nix build .#helixdb-docker-image
echo "✓ Image built"

echo -e "\n=== Loading Docker image ==="
docker load < $(nix build --print-out-paths .#helixdb-docker-image)
echo "✓ Image loaded"

echo -e "\n=== Starting container ==="
mkdir -p test-data
docker run -d \
  --name test-helix \
  -p 6969:6969 \
  -v $(pwd)/test-data:/data \
  -e HELIX_DATA_DIR=/data \
  helix-dev:latest
echo "✓ Container started"

echo -e "\n=== Waiting for startup ==="
sleep 3

echo -e "\n=== Testing health endpoint ==="
curl http://localhost:6969/health || echo "Health check failed"

echo -e "\n=== Testing search ==="
helix-search search "test" || echo "Search test failed"

# echo -e "\n=== Viewing logs ==="
# docker logs test-helix -f
# Function to perform the cleanup steps
#
#
cleanup() {
    echo -e "\n=== Cleanup ==="
    docker stop test-helix
    docker rm test-helix
    echo "✓ Test complete!"
    exit 1  # Exit the script after cleanup, using a non-zero exit code (e.g., 1)
  }

trap cleanup SIGINT

echo "Script is running. Press Ctrl+C to interrupt."
