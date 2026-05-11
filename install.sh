#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║    hash256 GPU Miner - One-Command Installer     ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ======== Check root ========
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[x] Run as root: sudo bash install.sh${NC}"
  exit 1
fi

# ======== Check NVIDIA driver ========
if ! command -v nvidia-smi &>/dev/null; then
  echo -e "${RED}[x] nvidia-smi not found. Install NVIDIA drivers first.${NC}"
  echo -e "${YELLOW}    Ubuntu: sudo apt install -y nvidia-driver-550${NC}"
  exit 1
fi
echo -e "${GREEN}[+] GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)${NC}"
NUM_GPUS=$(nvidia-smi --list-gpus | wc -l)
echo -e "${GREEN}[+] Detected $NUM_GPUS GPU(s)${NC}"

# ======== [1/5] System packages ========
echo -e "\n${YELLOW}[1/5] Installing build tools + Node.js 20...${NC}"
apt-get update -qq
apt-get install -y -qq build-essential curl git tmux >/dev/null 2>&1

if ! command -v node &>/dev/null || [ "$(node -v 2>/dev/null | cut -dv -f2 | cut -d. -f1)" -lt 18 ]; then
  echo -e "${YELLOW}  Installing Node.js 20...${NC}"
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
  apt-get install -y -qq nodejs >/dev/null 2>&1 || true
fi
echo -e "${GREEN}  node: $(node --version)${NC}"

# ======== [2/5] CUDA toolkit ========
echo -e "\n${YELLOW}[2/5] Checking CUDA toolkit...${NC}"

# Cari nvcc di lokasi umum
NVCC=""
for p in /usr/local/cuda/bin/nvcc /usr/bin/nvcc $(which nvcc 2>/dev/null); do
  if [ -x "$p" ]; then NVCC="$p"; break; fi
done

if [ -z "$NVCC" ]; then
  echo -e "${YELLOW}  nvcc not found, installing nvidia-cuda-toolkit...${NC}"
  apt-get install -y -qq nvidia-cuda-toolkit >/dev/null 2>&1 || true
  for p in /usr/local/cuda/bin/nvcc /usr/bin/nvcc; do
    if [ -x "$p" ]; then NVCC="$p"; break; fi
  done
fi

if [ -z "$NVCC" ]; then
  echo -e "${RED}[x] nvcc still not found after install.${NC}"
  echo -e "${YELLOW}    Install manually: https://developer.nvidia.com/cuda-downloads${NC}"
  echo -e "${YELLOW}    Lalu jalankan ulang script ini.${NC}"
  exit 1
fi

export PATH="$(dirname $NVCC):$PATH"
echo -e "${GREEN}  nvcc: $($NVCC --version 2>/dev/null | grep release | awk '{print $5}' | tr -d ',') ($NVCC)${NC}"

# ======== [3/5] Clone / update repo ========
echo -e "\n${YELLOW}[3/5] Setting up repo...${NC}"
INSTALL_DIR="$HOME/Hasminer-GPU"
if [ -d "$INSTALL_DIR/.git" ]; then
  echo -e "${GREEN}  Repo exists, pulling latest...${NC}"
  cd "$INSTALL_DIR" && git pull --quiet
else
  git clone --depth 1 https://github.com/Verifiedlabs/Hasminer-GPU.git "$INSTALL_DIR" >/dev/null 2>&1
  cd "$INSTALL_DIR"
fi
echo -e "${GREEN}  Repo: $INSTALL_DIR${NC}"

# ======== [4/5] npm install ========
echo -e "\n${YELLOW}[4/5] Installing Node.js dependencies...${NC}"
npm install --silent >/dev/null 2>&1
echo -e "${GREEN}  Done${NC}"

# ======== [5/5] Compile CUDA binary ========
echo -e "\n${YELLOW}[5/5] Compiling CUDA miner...${NC}"

# Auto-detect GPU arch dari compute capability
CC=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '.')
if [ -n "$CC" ]; then
  GPU_ARCH="sm_${CC}"
else
  GPU_ARCH="${GPU_ARCH:-sm_86}"
fi

echo -e "${GREEN}  Architecture: $GPU_ARCH${NC}"
$NVCC -O3 -arch=$GPU_ARCH -o "$INSTALL_DIR/keccak_miner_cuda" "$INSTALL_DIR/keccak_miner_cuda.cu"
echo -e "${GREEN}  Binary: $INSTALL_DIR/keccak_miner_cuda${NC}"

# ======== Setup .env ========
if [ ! -f "$INSTALL_DIR/.env" ]; then
  cat > "$INSTALL_DIR/.env" <<EOF
# Wajib diisi
PRIVATE_KEY=0xGANTI_DENGAN_PRIVATE_KEY_HOT_WALLET

# RPC untuk baca state (public gratis, atau pakai Alchemy/Infura untuk lebih stabil)
RPC_URL=https://ethereum.publicnode.com

# RPC untuk submit TX (Flashbots default, jangan diganti kecuali tau alasannya)
SUBMIT_RPC=https://rpc.flashbots.net/fast

# Jumlah GPU (sesuaikan dengan jumlah GPU kamu)
NUM_GPUS=$NUM_GPUS

# Priority fee ke validator (Gwei). Naikkan kalau TX sering gagal masuk block.
TIP_GWEI=5

# Set 1 untuk disable clear screen (log scroll biasa, cocok untuk logging)
NO_CLEAR=0
EOF
  echo -e "${GREEN}  .env template dibuat di $INSTALL_DIR/.env${NC}"
fi

# ======== Done ========
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           Installation Complete!                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Langkah selanjutnya:\n"
echo -e "  ${YELLOW}1. Edit .env dan isi PRIVATE_KEY:${NC}"
echo -e "     ${CYAN}nano $INSTALL_DIR/.env${NC}"
echo ""
echo -e "  ${YELLOW}2. Jalankan miner:${NC}"
echo -e "     ${CYAN}cd $INSTALL_DIR && node miner.js${NC}"
echo ""
echo -e "  ${YELLOW}3. Untuk multi-GPU ($NUM_GPUS GPU terdeteksi):${NC}"
echo -e "     ${CYAN}cd $INSTALL_DIR && NUM_GPUS=$NUM_GPUS node miner.js${NC}"
echo ""
echo -e "  ${YELLOW}4. Jalankan di background (SSH-safe):${NC}"
echo -e "     ${CYAN}tmux new -s miner${NC}"
echo -e "     ${CYAN}cd $INSTALL_DIR && NUM_GPUS=$NUM_GPUS node miner.js${NC}"
echo -e "     ${CYAN}# Detach: Ctrl+b lalu d | Reattach: tmux attach -t miner${NC}"
echo ""
echo -e "  ${YELLOW}Kalau layar kedap-kedip:${NC}"
echo -e "     ${CYAN}NO_CLEAR=1 NUM_GPUS=$NUM_GPUS node miner.js${NC}"
echo ""
