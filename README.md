# hash256 GPU Miner

CUDA-based miner for [HASH](https://hash256.org) on Ethereum mainnet.

## Requirements

- NVIDIA GPU with CUDA support (RTX 20xx+, compute capability 7.5+)
- CUDA Toolkit 11+
- Node.js 18+
- Ethereum wallet with ETH for gas fees

## Setup

```bash
git clone https://github.com/Verifiedlabs/Hasminer-GPU.git
cd Hasminer-GPU

chmod +x build.sh
./build.sh
```

By default compiles for `sm_86` (RTX 30xx). Override with:

```bash
GPU_ARCH=sm_89 ./build.sh   # RTX 40xx
GPU_ARCH=sm_75 ./build.sh   # RTX 20xx
```

## Run

```bash
export PRIVATE_KEY="0xyour_wallet_private_key"
export RPC_URL="https://your-alchemy-or-infura-url"

node miner.js
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PRIVATE_KEY` | required | Wallet private key for signing mint TX |
| `RPC_URL` | fallback pool | Read RPC (Alchemy/Infura recommended) |
| `SUBMIT_RPC` | `https://rpc.flashbots.net/fast` | Private mempool RPC for TX submission |
| `TIP_GWEI` | `15` | Priority fee tip in Gwei |

## vast.ai Setup

Rent any NVIDIA instance with CUDA pre-installed:

```bash
# On vast.ai instance
apt update && apt install -y nodejs npm git

git clone https://github.com/Verifiedlabs/Hasminer-GPU.git
cd Hasminer-GPU

export PATH=/usr/local/cuda/bin:$PATH
./build.sh

export PRIVATE_KEY="0x..."
node miner.js
```

## Performance

- RTX 3070: ~500 MH/s
- RTX 4090: ~2 GH/s

## Notes

Uses Flashbots private mempool by default to bypass public mempool MEV races. Validators include private-orderflow TXs ahead of public ones, significantly improving win rate at the block cap (10 mints per block).
