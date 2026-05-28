#!/usr/bin/env bash

# Shared build script for llama.cpp inside the container
# Located at /usr/bin/build-llama

set -e

if [ -n "$LLAMABOX_HOME_SOURCE" ]; then
    LLAMA_DIR="$HOME/llama.cpp"
else
    LLAMA_DIR="/opt/llama.cpp"
    # Ensure the directory exists and is writable by the current user
    if [ ! -d "$LLAMA_DIR" ]; then
        sudo mkdir -p "$LLAMA_DIR"
        sudo chown "$(id -u):$(id -g)" "$LLAMA_DIR"
    fi
fi
BUILD_DIR="$LLAMA_DIR/build"

# 1. Clone or update llama.cpp
if [ ! -d "$LLAMA_DIR" ]; then
    echo "Cloning llama.cpp..."
    git clone https://github.com/ggml-org/llama.cpp "$LLAMA_DIR"
fi

cd "$LLAMA_DIR"
echo "Updating llama.cpp..."
git pull

# Determine variant for build directory suffix
VARIANT="unknown"
if [ -f "/usr/bin/build-llama-cuda" ]; then
    VARIANT="cuda"
elif [ -f "/usr/bin/build-llama-rocm" ]; then
    VARIANT="rocm"
elif [ -f "/usr/bin/build-llama-sycl" ]; then
    VARIANT="sycl"
elif [ -f "/usr/bin/build-llama-vulkan" ]; then
    VARIANT="vulkan"
fi

# Use a dedicated build directory per variant to avoid cache poisoning
export BUILD_DIR="${LLAMA_DIR}/build-$VARIANT"
echo "Using build directory: $BUILD_DIR"

# 2. Determine backend and run variant-specific build
VARIANT_SCRIPT="/usr/bin/build-llama-$VARIANT"
if [ ! -f "$VARIANT_SCRIPT" ]; then
    echo "Error: No variant-specific build script found at $VARIANT_SCRIPT"
    exit 1
fi

echo "Found variant script: $VARIANT_SCRIPT"
source "$VARIANT_SCRIPT"

# 3. Symlink built binaries to /usr/local/bin for easy export
# Assuming the variant script ran cmake and cmake --build
# Use sudo as /usr/local/bin is root-owned
sudo mkdir -p /usr/local/bin
sudo find "$BUILD_DIR/bin" -maxdepth 1 -executable -type f -exec ln -sf {} /usr/local/bin/ \;

echo "Build and symlinking complete."
