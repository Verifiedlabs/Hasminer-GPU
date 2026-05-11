#!/bin/bash
set -e

echo "Installing Node.js dependencies..."
npm install

echo "Compiling CUDA miner..."
export PATH=/usr/local/cuda/bin:$PATH

if ! command -v nvcc &> /dev/null; then
    echo "Error: nvcc not found. Make sure CUDA toolkit is installed and in PATH."
    exit 1
fi

GPU_ARCH="${GPU_ARCH:-sm_86}"
echo "Using GPU architecture: $GPU_ARCH"

nvcc -O3 -arch=$GPU_ARCH -o keccak_miner_cuda keccak_miner_cuda.cu

echo "Done. Run: node miner.js"
