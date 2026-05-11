# hash256 GPU Miner

CUDA-based GPU miner for [HASH256](https://hash256.org) on Ethereum mainnet. Supports multi-GPU, auto-detects architecture, and submits via Flashbots private mempool to avoid MEV frontrunning.

## Performance

| GPU | Hashrate |
|-----|----------|
| RTX 2080 Ti | ~400 MH/s |
| RTX 3070 | ~500 MH/s |
| RTX 3090 | ~1.4 GH/s |
| RTX 4090 | ~2 GH/s |

Multi-GPU scales linearly. 5× RTX 3090 = ~7 GH/s.

## Requirements

- Ubuntu 20.04+ (atau distro Linux lain)
- NVIDIA GPU RTX 20xx atau lebih baru
- NVIDIA Driver 520+
- CUDA Toolkit 11+ (atau 12+)
- Node.js 18+
- ETH di wallet untuk gas fee

## Quick Install (Ubuntu, satu command)

```bash
curl -fsSL https://raw.githubusercontent.com/Verifiedlabs/Hasminer-GPU/main/install.sh | sudo bash
```

Script ini otomatis:
- Install CUDA toolkit, Node.js, build tools
- Clone repo
- Compile CUDA binary sesuai GPU kamu
- Tampilkan langkah selanjutnya

## Manual Setup

### 1. Install dependencies

```bash
sudo apt update
sudo apt install -y build-essential git curl

# Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
```

Pastikan CUDA Toolkit sudah terinstall dan `nvcc` bisa dijalankan:
```bash
nvcc --version
# Kalau tidak ditemukan:
export PATH=/usr/local/cuda/bin:$PATH
```

### 2. Clone repo

```bash
git clone https://github.com/Verifiedlabs/Hasminer-GPU.git
cd Hasminer-GPU
npm install
```

### 3. Compile CUDA binary

```bash
# RTX 20xx
GPU_ARCH=sm_75 ./build.sh

# RTX 30xx (default)
./build.sh

# RTX 40xx
GPU_ARCH=sm_89 ./build.sh

# RTX 50xx
GPU_ARCH=sm_120 ./build.sh
```

Kalau berhasil, akan ada file `keccak_miner_cuda` di folder repo.

### 4. Setup environment

Buat file `.env` di folder repo:

```bash
cp .env.example .env
nano .env
```

Isi minimal:

```env
PRIVATE_KEY=0xPRIVATE_KEY_HOT_WALLET_KAMU
RPC_URL=https://ethereum.publicnode.com
```

> **PENTING**: Gunakan hot wallet khusus mining, bukan wallet utama. Wallet ini butuh sedikit ETH untuk gas fee saat submit mint transaction.

### 5. Jalankan miner

```bash
# 1 GPU
node miner.js

# Multi GPU (contoh 5 GPU)
NUM_GPUS=5 node miner.js

# Dengan semua opsi
PRIVATE_KEY=0x... RPC_URL=https://... NUM_GPUS=5 TIP_GWEI=5 node miner.js
```

### 6. Jalankan di background (wajib kalau pakai SSH)

Pakai `tmux` biar miner tetap jalan walau SSH putus:

```bash
# Install tmux kalau belum ada
sudo apt install -y tmux

# Buat session baru
tmux new -s miner

# Jalankan miner di dalam tmux
NUM_GPUS=5 node miner.js

# Detach (miner tetap jalan di background): Ctrl+b lalu d
# Reattach nanti: tmux attach -t miner
```

## Environment Variables

| Variable | Default | Keterangan |
|----------|---------|------------|
| `PRIVATE_KEY` | **wajib** | Private key wallet untuk sign mint TX |
| `RPC_URL` | fallback public | RPC untuk baca state (Alchemy/Infura lebih stabil) |
| `SUBMIT_RPC` | `https://rpc.flashbots.net/fast` | RPC untuk submit TX |
| `NUM_GPUS` | `1` | Jumlah GPU yang dipakai |
| `TIP_GWEI` | `15` | Priority fee ke validator (Gwei) |
| `NO_CLEAR` | `0` | Set `1` untuk disable clear screen (log scroll biasa) |
| `USE_BUNDLE` | `true` | Set `false` untuk disable Flashbots bundle |

## Display Output

```
  era:         0
  reward:      100.0 HASH
  difficulty:  0x00000000…ffffff
  epoch:       250723 (rotates in 10 blk ~2m 0s)
  minted:      1,728,900.0 HASH
  remaining:   17,171,100.0 HASH
  balance:     0.0 HASH
  challenge:   0xa73d71a253…788eb0
  tx:          —

  searching · 7.49 GH/s · 3,123,948,245,109 hashes · 6m 57s · ETA ~10h 19m
```

- **era**: Era mining saat ini
- **reward**: Reward per mint (HASH token)
- **difficulty**: Target hash yang harus dicapai
- **epoch**: Epoch saat ini, challenge rotate tiap epoch
- **balance**: Saldo HASH di wallet kamu
- **ETA**: Estimasi waktu sampai nonce ketemu (luck-based, bisa lebih cepat/lambat)

Kalau layar kedap-kedip ganggu, jalankan dengan `NO_CLEAR=1`:
```bash
NO_CLEAR=1 NUM_GPUS=5 node miner.js
```

## Flashbots

Miner ini submit TX via [Flashbots](https://flashbots.net) private mempool secara default. Keuntungannya:

- TX tidak terlihat di public mempool → tidak bisa di-frontrun MEV bot
- Kalau nonce sudah diambil orang lain sebelum TX masuk block, TX otomatis dibatalkan tanpa buang gas
- Validator prioritaskan bundle dengan tip lebih tinggi

Atur `TIP_GWEI` sesuai kondisi jaringan:
- Sepi: `TIP_GWEI=1`
- Normal: `TIP_GWEI=5`
- Kompetitif: `TIP_GWEI=10-25`

## vast.ai / Cloud GPU

```bash
# Setelah instance ready
apt update && apt install -y nodejs npm git
export PATH=/usr/local/cuda/bin:$PATH

curl -fsSL https://raw.githubusercontent.com/Verifiedlabs/Hasminer-GPU/main/install.sh | bash

cd ~/Hasminer-GPU
NUM_GPUS=$(nvidia-smi --list-gpus | wc -l) node miner.js
```

## Troubleshooting

**`nvcc not found`**
```bash
export PATH=/usr/local/cuda/bin:$PATH
# Atau install CUDA toolkit: https://developer.nvidia.com/cuda-downloads
```

**`keccak_miner_cuda binary not found`**
```bash
./build.sh  # compile ulang
```

**TX tidak masuk / terus pending**
- Naikkan `TIP_GWEI`
- Coba RPC yang lebih reliable (Alchemy/Infura)

**Hashrate rendah**
- Pastikan `NUM_GPUS` sesuai jumlah GPU fisik
- Cek semua GPU terdeteksi: `nvidia-smi --list-gpus`
- Pastikan GPU tidak thermal throttle: `watch -n1 nvidia-smi`
