const { ethers } = require("ethers");
const { spawn } = require("child_process");
const path = require("path");
const fs = require("fs");
const ABI = require("./abi");

try { require("dotenv").config(); } catch {}

const CONTRACT = "0xAC7b5d06fa1e77D08aea40d46cB7C5923A87A0cc";
const BINARY = path.join(__dirname, "keccak_miner_cuda");

if (!fs.existsSync(BINARY)) {
  console.error("keccak_miner_cuda binary not found. Run ./build.sh first.");
  process.exit(1);
}

const NUM_GPUS = parseInt(process.env.NUM_GPUS || "1");

function fmtHashrate(hps) {
  if (hps >= 1e9) return (hps / 1e9).toFixed(2) + " GH/s";
  if (hps >= 1e6) return (hps / 1e6).toFixed(2) + " MH/s";
  if (hps >= 1e3) return (hps / 1e3).toFixed(2) + " kH/s";
  return hps.toFixed(0) + " H/s";
}

function fmtNumber(n) {
  return n.toLocaleString("en-US");
}

function fmtDuration(sec) {
  if (sec < 60) return sec.toFixed(1) + "s";
  if (sec < 3600) return Math.floor(sec / 60) + "m " + Math.floor(sec % 60) + "s";
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  return h + "h " + m + "m";
}

function short(hex, head = 6, tail = 4) {
  if (!hex) return "—";
  const s = String(hex);
  if (s.length < head + tail + 2) return s;
  return s.slice(0, head + 2) + "…" + s.slice(-tail);
}

const state = {
  era: 0n,
  reward: 0n,
  target: 0n,
  targetHex: "",
  minted: 0n,
  remaining: 0n,
  epoch: 0n,
  epochBlocksLeft: 0n,
  balance: 0n,
  challenge: "",
  hashrate: 0,
  totalHashes: 0,
  searchStart: Date.now(),
  status: "starting",
  tx: "—",
};

function render() {
  const targetShort = state.targetHex
    ? "0x" + state.targetHex.slice(0, 8) + "…" + state.targetHex.slice(-6)
    : "—";
  const epochTime = fmtDuration(Number(state.epochBlocksLeft) * 12);
  const elapsed = (Date.now() - state.searchStart) / 1000;
  const maxVal = BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
  const prob = state.target > 0n ? Number(state.target) / Number(maxVal) : 0;
  const expected = prob > 0 ? 1 / prob : 0;
  const remaining = Math.max(0, expected - state.totalHashes);
  const eta = state.hashrate > 0 ? remaining / state.hashrate : 0;

  const lines = [
    "",
    "  era:         " + state.era.toString(),
    "  reward:      " + ethers.formatEther(state.reward) + " HASH",
    "  difficulty:  " + targetShort,
    "  epoch:       " + state.epoch.toString() + " (rotates in " + state.epochBlocksLeft.toString() + " blk ~" + epochTime + ")",
    "  minted:      " + ethers.formatEther(state.minted) + " HASH",
    "  remaining:   " + ethers.formatEther(state.remaining) + " HASH",
    "  balance:     " + ethers.formatEther(state.balance) + " HASH",
    "  challenge:   " + short(state.challenge, 10, 6),
    "  tx:          " + state.tx,
    "",
    "  " + state.status + " · " + fmtHashrate(state.hashrate) + " · " +
      fmtNumber(Math.floor(state.totalHashes)) + " hashes · " +
      fmtDuration(elapsed) + " · ETA ~" + fmtDuration(eta),
    "",
  ];
  process.stdout.write("\x1b[H\x1b[J" + lines.join("\n"));
}

async function main() {
  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) {
    console.error("Set PRIVATE_KEY env variable");
    process.exit(1);
  }

  const readProvider = process.env.RPC_URL
    ? new ethers.JsonRpcProvider(process.env.RPC_URL)
    : new ethers.FallbackProvider([
        { provider: new ethers.JsonRpcProvider("https://ethereum.publicnode.com"), priority: 1, weight: 1 },
        { provider: new ethers.JsonRpcProvider("https://1rpc.io/eth"), priority: 2, weight: 1 },
      ], 1);

  const submitRpc = process.env.SUBMIT_RPC || "https://rpc.flashbots.net/fast";
  const submitProvider = new ethers.JsonRpcProvider(submitRpc);

  const readWallet = new ethers.Wallet(privateKey, readProvider);
  const submitWallet = new ethers.Wallet(privateKey, submitProvider);
  const readContract = new ethers.Contract(CONTRACT, ABI, readWallet);
  const submitContract = new ethers.Contract(CONTRACT, ABI, submitWallet);

  console.log("─".repeat(60));
  console.log("  hash256 GPU miner (CUDA)");
  console.log("─".repeat(60));
  console.log("  address:    ", readWallet.address);
  console.log("  gpus:       ", NUM_GPUS);
  console.log("  read rpc:   ", process.env.RPC_URL || "fallback");
  console.log("  submit rpc: ", submitRpc);
  console.log("─".repeat(60));
  await new Promise(r => setTimeout(r, 1000));

  await run(readContract, submitContract, readWallet, readProvider);
}

async function fetchState(contract, address) {
  const [challenge, ms, balance] = await Promise.all([
    contract.getChallenge(address),
    contract.miningState(),
    contract.balanceOf(address)
  ]);
  return {
    challenge,
    era: ms[0],
    reward: ms[1],
    target: ms[2],
    minted: ms[3],
    remaining: ms[4],
    epoch: ms[5],
    epochBlocksLeft: ms[6],
    balance
  };
}

async function run(readContract, submitContract, wallet, provider) {
  let initial = await fetchState(readContract, wallet.address);
  applyState(initial);
  state.status = "searching";
  state.searchStart = Date.now();
  state.totalHashes = 0;
  render();

  const workers = [];
  const hashrates = new Array(NUM_GPUS).fill(0);

  let submitting = false;
  let lastEpoch = state.epoch;

  for (let gpu = 0; gpu < NUM_GPUS; gpu++) {
    const proc = spawn(BINARY, [initial.challenge, "0x" + state.targetHex], {
      env: { ...process.env, CUDA_VISIBLE_DEVICES: String(gpu) }
    });

    proc.stdout.on("data", async (data) => {
      for (const line of data.toString().split("\n")) {
        if (!line.startsWith("FOUND:")) continue;
        if (submitting) continue;
        submitting = true;
        const nonce = line.slice(6);
        state.status = "submitting (gpu " + gpu + ")";
        render();
        try {
          const currentState = await readContract.miningState();
          if (currentState[5].toString() !== state.epoch.toString()) {
            state.status = "epoch rotated before submit, skipping";
            submitting = false;
            const s = await fetchState(readContract, wallet.address);
            applyState(s);
            lastEpoch = s.epoch;
            broadcastUpdate(workers, s.challenge, state.targetHex);
            state.totalHashes = 0;
            state.searchStart = Date.now();
            state.status = "searching";
            return;
          }
          const feeData = await provider.getFeeData();
          const tipGwei = process.env.TIP_GWEI || "15";
          const priorityFee = ethers.parseUnits(tipGwei, "gwei");
          const baseFee = feeData.maxFeePerGas || 0n;
          const maxFeePerGas = baseFee > priorityFee ? baseFee : priorityFee * 2n;
          const tx = await submitContract.mine(BigInt("0x" + nonce), {
            gasLimit: 300000n,
            maxFeePerGas,
            maxPriorityFeePerGas: priorityFee,
          });
          state.tx = tx.hash;
          render();
          const receipt = await tx.wait();
          state.status = "confirmed in block " + receipt.blockNumber;
          const s = await fetchState(readContract, wallet.address);
          applyState(s);
          lastEpoch = s.epoch;
        } catch (err) {
          state.status = "error: " + (err.shortMessage || err.message);
        }
        submitting = false;
        broadcastUpdate(workers, state.challenge, state.targetHex);
        state.totalHashes = 0;
        state.searchStart = Date.now();
        state.status = "searching";
      }
    });

    proc.stderr.on("data", (data) => {
      for (const line of data.toString().split("\n")) {
        if (line.startsWith("PROGRESS:")) {
          const parts = line.split(":");
          hashrates[gpu] = parseInt(parts[2]);
          state.hashrate = hashrates.reduce((a, b) => a + b, 0);
          state.totalHashes = state.hashrate * ((Date.now() - state.searchStart) / 1000);
        }
      }
    });

    proc.on("exit", () => {
      console.log("\nminer gpu " + gpu + " exited");
      process.exit(1);
    });

    workers.push(proc);
  }

  const renderTimer = setInterval(render, 500);

  const stateTimer = setInterval(async () => {
    try {
      const s = await fetchState(readContract, wallet.address);
      applyState(s);
      if (s.epoch.toString() !== lastEpoch.toString() && !submitting) {
        lastEpoch = s.epoch;
        broadcastUpdate(workers, s.challenge, state.targetHex);
        state.totalHashes = 0;
        state.searchStart = Date.now();
      }
    } catch {}
  }, 12000);
}

function broadcastUpdate(workers, challenge, targetHex) {
  const msg = "UPDATE 0x" + challenge.slice(2) + " 0x" + targetHex + "\n";
  for (const w of workers) {
    try { w.stdin.write(msg); } catch {}
  }
}

function applyState(s) {
  state.era = s.era;
  state.reward = s.reward;
  state.target = s.target;
  state.targetHex = s.target.toString(16).padStart(64, "0");
  state.minted = s.minted;
  state.remaining = s.remaining;
  state.epoch = s.epoch;
  state.epochBlocksLeft = s.epochBlocksLeft;
  state.balance = s.balance;
  state.challenge = s.challenge;
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
