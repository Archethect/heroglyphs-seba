// Read-only planner for the first public Hoodi V1 rehearsal transaction.
// Never imports a signer, signs, sends, or broadcasts a transaction.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseEnv } from "node:util";
import { ethers } from "ethers";
import { currentSource } from "./hoodi-source-gate.mjs";

export const HOODI_CHAIN_ID = 560048n;
export const HOODI_ADMIN = "0x00008A88A21a1d34CDDAA7fC15A0E84ed7e42D8f";
export const SAFE_SINGLETON = "0x41675C099F32341bf84BFc5382aF534df5C7461a";
export const SAFE_FACTORY = "0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67";
export const SAFE_MULTISEND = "0x38869bf66a61cF6bDB996A6aE40D5853Fd43B526";
export const SAFE_SALT_NONCE = 0x5eban;

const EXPECTED_CODE_HASHES = new Map([
  [SAFE_SINGLETON, "0x1fe2df852ba3299d6534ef416eefa406e56ced995bca886ab7a553e6d0c5e1c4"],
  [SAFE_FACTORY, "0x50c3cdc4074750a7a974204a716c999edd37482f907608d960b2b025ee0b3317"],
  [SAFE_MULTISEND, "0x0e4f7fc66550a322d1e7688e181b75e217e662a4f3f4d6a29b22bc61217c4b77"],
]);
const SAFE_ABI = [
  "function setup(address[] owners,uint256 threshold,address to,bytes data,address fallbackHandler,address paymentToken,uint256 payment,address payable paymentReceiver)",
];
const FACTORY_ABI = [
  "function createProxyWithNonce(address singleton,bytes initializer,uint256 saltNonce) returns (address proxy)",
];

export function requireHoodiChain(chainId) {
  if (BigInt(chainId) !== HOODI_CHAIN_ID) throw new Error("Refusing non-Hoodi RPC before transaction planning");
}

export function requireExpectedCodeHash(address, code) {
  const expected = EXPECTED_CODE_HASHES.get(ethers.getAddress(address));
  if (!expected || code === "0x" || ethers.keccak256(code) !== expected) {
    throw new Error(`Hoodi dependency code hash mismatch: ${address}`);
  }
}

export function safeFactoryPayload() {
  const initializer = safeInitializer();
  return new ethers.Interface(FACTORY_ABI).encodeFunctionData("createProxyWithNonce", [
    SAFE_SINGLETON,
    initializer,
    SAFE_SALT_NONCE,
  ]);
}

function safeInitializer() {
  return new ethers.Interface(SAFE_ABI).encodeFunctionData("setup", [
    [HOODI_ADMIN],
    1,
    ethers.ZeroAddress,
    "0x",
    ethers.ZeroAddress,
    ethers.ZeroAddress,
    0,
    ethers.ZeroAddress,
  ]);
}

export async function planHoodiSafe(provider, source = currentSource()) {
  requireHoodiChain(await provider.send("eth_chainId", []));
  const block = await provider.getBlock("latest");
  if (!block?.hash) throw new Error("Missing Hoodi head block");
  for (const address of EXPECTED_CODE_HASHES.keys()) {
    requireExpectedCodeHash(address, await provider.getCode(address, block.number));
  }
  const data = safeFactoryPayload();
  const factory = new ethers.Contract(SAFE_FACTORY, FACTORY_ABI, provider);
  const predictedSafe = await factory.createProxyWithNonce.staticCall(
    SAFE_SINGLETON,
    safeInitializer(),
    SAFE_SALT_NONCE,
    { from: HOODI_ADMIN },
  );
  if ((await provider.getCode(predictedSafe)) !== "0x")
    throw new Error("Reviewed Safe salt already used; choose a new salt");
  const request = { from: HOODI_ADMIN, to: SAFE_FACTORY, value: 0n, data };
  const estimatedGas = await provider.estimateGas(request);
  const gasLimit = (estimatedGas * 125n) / 100n;
  const fees = await provider.getFeeData();
  const maxFeePerGas = fees.maxFeePerGas ?? fees.gasPrice;
  if (!maxFeePerGas) throw new Error("Hoodi gas fee unavailable");
  const maximumGasCostWei = gasLimit * maxFeePerGas;
  const balanceWei = await provider.getBalance(HOODI_ADMIN);
  if (balanceWei < maximumGasCostWei) throw new Error("Hoodi admin wallet cannot cover maximum gas cost");
  const latestNonce = await provider.getTransactionCount(HOODI_ADMIN, "latest");
  const pendingNonce = await provider.getTransactionCount(HOODI_ADMIN, "pending");
  if (latestNonce !== pendingNonce) throw new Error("Hoodi admin wallet has pending transactions; review nonce first");
  return {
    schemaVersion: "seba-hoodi-public-safe-plan-v1",
    readOnly: true,
    broadcast: false,
    executionReady: !source.worktreeDirty,
    network: "hoodi",
    chainId: Number(HOODI_CHAIN_ID),
    source,
    observedAt: { blockNumber: block.number, blockHash: block.hash },
    dependencies: Object.fromEntries(EXPECTED_CODE_HASHES),
    signer: { address: HOODI_ADMIN, method: "owner-wallet-ui", nonce: pendingNonce },
    safe: {
      expectedAddress: predictedSafe,
      singleton: SAFE_SINGLETON,
      owners: [HOODI_ADMIN],
      threshold: 1,
      saltNonce: SAFE_SALT_NONCE.toString(),
    },
    transaction: {
      to: SAFE_FACTORY,
      from: HOODI_ADMIN,
      valueWei: "0",
      data,
      estimatedGas: estimatedGas.toString(),
      gasLimit: gasLimit.toString(),
      maxFeePerGasWei: maxFeePerGas.toString(),
      maxPriorityFeePerGasWei: fees.maxPriorityFeePerGas?.toString() ?? null,
      maximumGasCostWei: maximumGasCostWei.toString(),
      walletBalanceWei: balanceWei.toString(),
    },
    abortIf: [
      "Wallet network is not Hoodi (chain 560048).",
      "Recipient, zero ETH value, calldata, signer, or nonce differs from this reviewed plan.",
      "Safe factory/singleton/MultiSend code hash or predicted Safe address differs on recheck.",
      "The Safe address already has code, or a pending admin transaction appears.",
      "The fee ceiling or gas estimate changes materially; regenerate and review this plan.",
    ],
  };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const envFileArg = process.argv[2];
  if (!envFileArg || process.argv.length !== 3)
    throw new Error("Usage: node tools/hoodi-public-safe-plan.mjs <ignored-local-env-file>");
  const loaded = parseEnv(fs.readFileSync(envFileArg, "utf8"));
  const rpc = process.env.HOODI_RPC || loaded.HOODI_RPC;
  if (!rpc) throw new Error("HOODI_RPC missing");
  const provider = new ethers.JsonRpcProvider(rpc);
  console.log(JSON.stringify(await planHoodiSafe(provider), null, 2));
}
