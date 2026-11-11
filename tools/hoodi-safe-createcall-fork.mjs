// Local-only Hoodi fork proof. No public transaction, signer key, or broadcast path.
import fs from "node:fs";
import net from "node:net";
import path from "node:path";
import { spawn } from "node:child_process";
import { parseEnv } from "node:util";
import { ethers } from "ethers";
import { CREATE_CALL, CREATE_CALL_CODE_HASH, create2Deployment, multiSendData } from "./hoodi-safe-createcall.mjs";
import { HOODI_ADMIN, SAFE_MULTISEND } from "./hoodi-public-safe-plan.mjs";
import { buildHoodiV1Plan } from "./hoodi-public-v1-plan.mjs";
import { HOODI_V1_RUNTIME_HASHES } from "./hoodi-public-v1-runtime.mjs";
import { verifyHoodiV1Batch } from "./hoodi-public-v1-verify.mjs";

const SAFE_TX = "0x3ac6307b93523487a9d39c079801994e6363d445f13554483f6540279d31fdf6";
const SAFE = "0xAc52395a9D706696Cf36125A0664c0C6d2B06B7b";
const MULTISEND_HASH = "0x0e4f7fc66550a322d1e7688e181b75e217e662a4f3f4d6a29b22bc61217c4b77";
const SAFE_ABI = [
  "function nonce() view returns(uint256)",
  "function getTransactionHash(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,uint256) view returns(bytes32)",
  "function approveHash(bytes32)",
  "function execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes) returns(bool)",
  "event ExecutionSuccess(bytes32 indexed txHash,uint256 payment)",
];

function artifact(name) {
  const raw = JSON.parse(fs.readFileSync(path.resolve(`out/${name}.sol/${name}.json`), "utf8"));
  if (!raw.bytecode?.object || raw.bytecode.object === "0x") throw new Error(`missing ${name} artifact`);
  return raw.bytecode.object;
}

async function freePort() {
  const server = net.createServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;
  await new Promise((resolve) => server.close(resolve));
  return port;
}

async function main() {
  if (process.argv.length < 3 || process.argv.length > 4 || (process.argv[3] && process.argv[3] !== "full")) {
    throw new Error("Usage: node tools/hoodi-safe-createcall-fork.mjs <ignored-env-file> [full]");
  }
  const loaded = parseEnv(fs.readFileSync(process.argv[2], "utf8"));
  const rpc = process.env.HOODI_RPC || loaded.HOODI_RPC;
  if (!rpc) throw new Error("HOODI_RPC missing");
  const publicHoodi = new ethers.JsonRpcProvider(rpc);
  if (BigInt(await publicHoodi.send("eth_chainId", [])) !== 560048n) throw new Error("not Hoodi");
  const safeReceipt = await publicHoodi.getTransactionReceipt(SAFE_TX);
  if (safeReceipt?.status !== 1) throw new Error("verified Safe transaction missing");
  const port = await freePort();
  const child = spawn(
    "anvil",
    [
      "--fork-url",
      rpc,
      "--fork-block-number",
      String(safeReceipt.blockNumber),
      "--chain-id",
      "560048",
      "--host",
      "127.0.0.1",
      "--port",
      String(port),
      "--silent",
    ],
    { stdio: "ignore" },
  );
  try {
    const local = new ethers.JsonRpcProvider(`http://127.0.0.1:${port}`);
    let ready = false;
    for (let i = 0; i < 100; i++) {
      if (child.exitCode !== null) throw new Error("Anvil exited before fork was ready");
      try {
        ready = BigInt(await local.send("eth_chainId", [])) === 560048n;
        if (ready) break;
      } catch {
        /* startup */
      }
      await new Promise((resolve) => setTimeout(resolve, 200));
    }
    if (!ready) throw new Error("local Hoodi fork did not start");
    const head = await local.getBlock("latest");
    if (head?.hash !== safeReceipt.blockHash) throw new Error("local fork anchor mismatch");
    for (const [address, expectedHash] of [
      [CREATE_CALL, CREATE_CALL_CODE_HASH],
      [SAFE_MULTISEND, MULTISEND_HASH],
    ]) {
      if (ethers.keccak256(await local.getCode(address)) !== expectedHash)
        throw new Error(`code hash mismatch: ${address}`);
    }
    if ((await local.getCode(SAFE)) === "0x") throw new Error("Safe missing on fork");
    await local.send("anvil_impersonateAccount", [HOODI_ADMIN]);
    await local.send("anvil_setBalance", [HOODI_ADMIN, ethers.toBeHex(ethers.parseEther("10"))]);
    const owner = await local.getSigner(HOODI_ADMIN);
    const safe = new ethers.Contract(SAFE, SAFE_ABI, owner);
    const full = process.argv[3] === "full";
    const plan = full ? await buildHoodiV1Plan(SAFE, HOODI_ADMIN) : undefined;
    const deployments = full
      ? plan.deployments
      : ["MockWETH", "MockUSDC"].map((name) => ({
          name,
          ...create2Deployment(artifact(name), ethers.id(`seba-hoodi-createcall-fork-probe:${name}`)),
        }));
    for (const deployment of deployments) {
      if ((await local.getCode(deployment.expectedAddress)) !== "0x")
        throw new Error("CREATE2 address already occupied");
    }
    const batches = full ? plan.batches : [{ name: "smoke", calls: deployments }];
    const batchResults = [];
    for (const item of batches) {
      const data = multiSendData(item.calls);
      const nonce = await safe.nonce();
      const txHash = await safe.getTransactionHash(
        SAFE_MULTISEND,
        0,
        data,
        1,
        0,
        0,
        0,
        ethers.ZeroAddress,
        ethers.ZeroAddress,
        nonce,
      );
      if (txHash === ethers.ZeroHash) throw new Error("invalid Safe transaction hash");
      // The sole owner EOA executes directly; Safe's prevalidated v=1 signature needs no approveHash tx.
      const signature = ethers.concat([ethers.zeroPadValue(HOODI_ADMIN, 32), ethers.ZeroHash, "0x01"]);
      const request = [SAFE_MULTISEND, 0, data, 1, 0, 0, 0, ethers.ZeroAddress, ethers.ZeroAddress, signature];
      const estimatedGas = await safe.execTransaction.estimateGas(...request);
      const receipt = await (await safe.execTransaction(...request, { gasLimit: estimatedGas * 2n })).wait();
      if (
        receipt.status !== 1 ||
        !receipt.logs.some((log) => {
          try {
            return safe.interface.parseLog(log)?.name === "ExecutionSuccess";
          } catch {
            return false;
          }
        })
      )
        throw new Error(`local Safe batch failed: ${item.name}`);
      if (full) await verifyHoodiV1Batch(local, receipt.hash, Number(nonce));
      for (const deployment of item.calls.filter((c) => c.expectedAddress)) {
        if ((await local.getCode(deployment.expectedAddress)) === "0x") throw new Error(`missing ${deployment.name}`);
      }
      batchResults.push({
        name: item.name,
        safeNonce: nonce.toString(),
        estimatedGas: estimatedGas.toString(),
        gasUsed: receipt.gasUsed.toString(),
        blockNumber: receipt.blockNumber,
      });
    }
    const result = [];
    for (const deployment of deployments) {
      const code = await local.getCode(deployment.expectedAddress);
      if (code === "0x") throw new Error(`missing ${deployment.name} deployment`);
      if (full && ethers.keccak256(code) !== HOODI_V1_RUNTIME_HASHES[deployment.label]) {
        throw new Error(`runtime code hash differs from reviewed manifest: ${deployment.label}`);
      }
      result.push({ name: deployment.name, address: deployment.expectedAddress, codeHash: ethers.keccak256(code) });
    }
    if (full) {
      const addr = (name) => plan.deployments.find((d) => d.name === name).expectedAddress;
      const roleAbi = ["function hasRole(bytes32,address) view returns(bool)"];
      const adminRole = ethers.id("ADMIN_ROLE");
      const automatorRole = ethers.id("AUTOMATOR_ROLE");
      for (const name of ["EthToBoldRouter", "PYBSeba", "SebaPool", "EUSDUSDCBeefyYieldVault", "YieldManager"]) {
        const c = new ethers.Contract(addr(name), roleAbi, local);
        if (!(await c.hasRole(adminRole, SAFE)) || (await c.hasRole(adminRole, HOODI_ADMIN))) {
          throw new Error(`V1 admin policy mismatch: ${name}`);
        }
      }
      for (const name of ["SebaPool", "YieldManager"]) {
        const c = new ethers.Contract(addr(name), roleAbi, local);
        if (!(await c.hasRole(automatorRole, HOODI_ADMIN))) throw new Error(`missing bounded V1 automator: ${name}`);
      }
      for (const [name, role] of [
        ["EthToBoldRouter", "YIELD_MANAGER_ROLE"],
        ["EUSDUSDCBeefyYieldVault", "YIELDMANAGER_ROLE"],
      ]) {
        const c = new ethers.Contract(addr(name), roleAbi, local);
        if (!(await c.hasRole(ethers.id(role), addr("YieldManager"))) || (await c.hasRole(ethers.id(role), SAFE))) {
          throw new Error(`V1 manager role mismatch: ${name}`);
        }
      }
      const pool = new ethers.Contract(
        addr("SebaPool"),
        ["function yieldManager() view returns(address)", "function sebaVault() view returns(address)"],
        local,
      );
      const pyb = new ethers.Contract(
        addr("PYBSeba"),
        ["function sebaPool() view returns(address)", "function balanceOf(address) view returns(uint256)"],
        local,
      );
      const manager = new ethers.Contract(
        addr("YieldManager"),
        [
          "function depositId() view returns(uint256)",
          "function principalValue() view returns(uint256)",
          "function pendingBoldConversion() view returns(uint256)",
        ],
        local,
      );
      if (
        (await pool.yieldManager()) !== addr("YieldManager") ||
        (await pool.sebaVault()) !== addr("PYBSeba") ||
        (await pyb.sebaPool()) !== addr("SebaPool")
      )
        throw new Error("V1 bindings mismatch");
      if (
        (await pyb.balanceOf(SAFE)) !== 1n ||
        (await manager.depositId()) !== 0n ||
        (await manager.principalValue()) !== 0n ||
        (await manager.pendingBoldConversion()) !== 0n
      )
        throw new Error("V1 clean-state mismatch");
    }
    console.log(
      JSON.stringify(
        {
          network: "local Hoodi fork",
          publicBroadcast: false,
          anchor: head.number,
          safe: SAFE,
          createCall: CREATE_CALL,
          batches: batchResults,
          deployments: result,
        },
        null,
        2,
      ),
    );
  } finally {
    child.kill("SIGTERM");
  }
}

await main();
