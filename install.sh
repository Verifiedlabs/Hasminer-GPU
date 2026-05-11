#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║    hash256 GPU Miner - One-Command Installer     ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

if ! command -v nvidia-smi &>/dev/null; then
  echo -e "${RED}[x] nvidia-smi not found. Install NVIDIA drivers first.${NC}"
  exit 1
fi
echo -e "${GREEN}[+] GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)${NC}"
NUM_GPUS=$(nvidia-smi --list-gpus | wc -l)
echo -e "${GREEN}[+] Detected $NUM_GPUS GPU(s)${NC}"

echo -e "\n${YELLOW}[1/4] Installing CUDA toolkit + gcc + Node.js 20...${NC}"
apt-get update -qq
apt-get install -y -qq nvidia-cuda-toolkit build-essential curl git >/dev/null 2>&1 || true
if ! command -v node &>/dev/null || [[ "$(node -v 2>/dev/null)" < "v18" ]]; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
  apt-get install -y -qq nodejs >/dev/null 2>&1 || dpkg -i --force-overwrite /var/cache/apt/archives/nodejs_*.deb >/dev/null 2>&1
  apt-get install -f -y >/dev/null 2>&1 || true
fi

echo -e "${GREEN}  nvcc: $(nvcc --version 2>/dev/null | grep release | awk '{print $5}' | tr -d ',')${NC}"
echo -e "${GREEN}  node: $(node --version)${NC}"

echo -e "\n${YELLOW}[2/4] Cloning repo...${NC}"
INSTALL_DIR="$HOME/Hasminer-GPU"
if [ -d "$INSTALL_DIR" ]; then
  cd "$INSTALL_DIR" && git pull --quiet
else
  git clone --depth 1 https://github.com/Verifiedlabs/Hasminer-GPU.git "$INSTALL_DIR" >/dev/null 2>&1
  cd "$INSTALL_DIR"
fi
echo -e "${GREEN}  Repo at: $INSTALL_DIR${NC}"

echo -e "\n${YELLOW}[3/4] Installing Node.js dependencies...${NC}"
npm install --silent >/dev/null 2>&1

echo -e "\n${YELLOW}[4/4] Compiling CUDA miner...${NC}"
GPU_ARCH="sm_86"
CC=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '.')
[ ! -z "$CC" ] && GPU_ARCH="sm_${CC}"
echo -e "${GREEN}  Architecture: $GPU_ARCH${NC}"
nvcc -O3 -arch=$GPU_ARCH -o keccak_miner_cuda keccak_miner_cuda.cu

echo -e "\n${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           Installation Complete                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo "  1. Export your wallet and RPC:"
echo "     ${CYAN}export PRIVATE_KEY=\"0xyour_wallet_private_key\"${NC}"
echo "     ${CYAN}export RPC_URL=\"https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY\"${NC}"
echo ""
echo "  2. Start mining (all $NUM_GPUS GPUs):"
echo "     ${CYAN}cd $INSTALL_DIR && NUM_GPUS=$NUM_GPUS node miner.js${NC}"
