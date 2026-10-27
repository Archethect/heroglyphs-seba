#!/usr/bin/env node
"use strict";
// This tool cannot target a public RPC. All deployments are disposable local Anvil fixtures.
const fs = require("node:fs");
const path = require("node:path");
const { JsonRpcProvider, ContractFactory, Contract, parseEther, keccak256, AbiCoder } = require("ethers");
const rpc = process.env.SEBA_V2_LOCAL_RPC || "http://127.0.0.1:28545";
const url = new URL(rpc);
if (
  url.protocol !== "http:" ||
  !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname) ||
  url.username ||
  url.password
)
  throw new Error("Local loopback Anvil only");
const ROOT = path.resolve(__dirname, "../..");
const out = process.argv[2] || "/private/tmp/seba-v2-local-fixture.json";
const appendLocal = process.argv[3] === "--append-local";
if (process.argv[3] && !appendLocal) throw new Error("Only --append-local is supported");
if (fs.existsSync(out)) throw new Error("Never overwrite a retained fixture; choose a new output path");
if (appendLocal && (url.port !== "28545" || url.search || url.pathname !== "/"))
  throw new Error("Appending is permitted only on isolated loopback Anvil :28545");
const SAFE = "0x888D768764A2E304215247F0bA3457cCb0f0ab4f";
const POOL = "0xe3B17b4533b339d3CBC26F57199d3fb937129894";
const OLD = "0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269";
const RETH = "0xae78736Cd615f374D3085123A210448E74Fc6393";
const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const BOLD = "0x6440f144b7e50D6a8439336510312d2F54beB01D";
const YBOLD = "0x9F4330700a36B29952869fac9b33f45EEdd8A3d8";
const YSY = "0x23346B04a7f55b8760E5860AA5A77383D63491cD";
const REGISTRY = "0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46";
const artifact = (file, name = file) =>
  JSON.parse(fs.readFileSync(path.join(ROOT, "out", `${file}.sol`, `${name}.json`)));
async function main() {
  const provider = new JsonRpcProvider(rpc, undefined, { cacheTimeout: -1 });
  const info = await provider.send("anvil_nodeInfo", []); // Public nodes do not expose this method.
  if (!(await provider.send("web3_clientVersion", [])).toLowerCase().includes("anvil")) throw new Error("Not Anvil");
  if ((await provider.getNetwork()).chainId !== 1n) throw new Error("Wrong local chain");
  const anchorBlock = Number(process.env.SEBA_V2_FORK_BLOCK || 26255470);
  const anchor = await provider.getBlock(anchorBlock);
  if (!anchor || (!appendLocal && Number(info.currentBlockNumber) !== anchorBlock))
    throw new Error("Use a fresh isolated fork at the selected anchor, never an existing test environment");
  if (
    appendLocal &&
    (anchorBlock !== 26255470 || anchor.hash !== "0xf25248665c0503187af12c445ae824d78f3b84994d18582dfc634ab30029839c")
  )
    throw new Error("Append requires the exact retained V2 rehearsal fork");
  const previousHead = await provider.getBlock("latest");
  const deployer = await provider.getSigner(0);
  const operator = await provider.getSigner(1);
  const operatorAddress = await operator.getAddress();
  const safeIdentity = new Contract(SAFE, ["function getOwners() view returns(address[])"], provider);
  const safeOwnersHash = keccak256(AbiCoder.defaultAbiCoder().encode(["address[]"], [await safeIdentity.getOwners()]));
  const old = new Contract(
    OLD,
    ["function sBOLD() view returns(address)", "function sebaVault() view returns(address)"],
    provider,
  );
  const SBOLD = await old.sBOLD();
  const PYB = await old.sebaVault();
  async function deploy(file, args = [], name = file) {
    const a = artifact(file, name);
    const factory = new ContractFactory(a.abi, a.bytecode.object, deployer);
    const contract = await factory.deploy(...args);
    const receipt = await contract.deploymentTransaction().wait();
    return {
      contract,
      metadata: {
        address: await contract.getAddress(),
        deploymentBlock: receipt.blockNumber,
        deploymentTransaction: receipt.hash,
        deploymentBlockHash: receipt.blockHash,
      },
    };
  }
  async function proxy(file, initialization) {
    const impl = await deploy(file);
    const data = impl.contract.interface.encodeFunctionData("initialize", initialization);
    const p = await deploy("ERC1967Proxy", [impl.metadata.address, data]);
    return {
      contract: new Contract(p.metadata.address, artifact(file).abi, deployer),
      metadata: { ...p.metadata, implementation: impl.metadata.address, implementationDeployment: impl.metadata },
    };
  }
  const manager = await proxy("YieldManagerV2", [
    {
      treasury: SAFE,
      operator: operatorAddress,
      pool: POOL,
      bold: BOLD,
      sBold: SBOLD,
      pybSeba: PYB,
      reth: RETH,
      ysyBold: YSY,
    },
  ]);
  const r = await proxy("RethSupporterVault", [SAFE, manager.metadata.address, RETH, REGISTRY]);
  const y = await proxy("YsyBoldSupporterVault", [SAFE, manager.metadata.address, YSY, YBOLD]);
  const executor = await deploy("SebaV2Executor", [
    {
      manager: manager.metadata.address,
      treasury: SAFE,
      reth: RETH,
      weth: WETH,
      usdc: USDC,
      bold: BOLD,
      yBold: YBOLD,
      ysyBold: YSY,
      swapRouter: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
      curvePool: "0xEFc6516323FbD28e80B85A497B65A86243a54B3E",
      ethUsdFeed: "0xc0053f3FBcCD593758258334Dfce24C2A9A673aD",
      usdcUsdFeed: "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6",
      rocketStorage: REGISTRY,
    },
  ]);
  await provider.send("anvil_impersonateAccount", [SAFE]);
  if (!appendLocal) await provider.send("anvil_setBalance", [SAFE, "0x" + parseEther("10").toString(16)]); // SYNTHETIC LOCAL GAS ONLY, not recovered capital.
  const safe = await provider.getSigner(SAFE);
  await (await manager.contract.connect(safe).bindVaults(r.metadata.address, y.metadata.address)).wait();
  // No entries, intake, execution, production parameters or pool-pointer change is enabled by this deployment tool.
  const manifest = {
    schema: "seba-v2-local-fixture-v1",
    chainId: 1,
    localOnly: true,
    mainnetFork: true,
    anchorBlock,
    anchorBlockHash: anchor.hash,
    anchorHash: anchor.hash,
    manager: manager.metadata,
    rethVault: r.metadata,
    ysyBoldVault: y.metadata,
    executor: executor.metadata,
    operator: operatorAddress,
    treasury: SAFE,
    safeOwnersHash,
    pool: POOL,
    oldManager: OLD,
    config: {
      operator: operatorAddress,
      treasury: SAFE,
      pool: POOL,
      bold: BOLD,
      sBold: SBOLD,
      pybSeba: PYB,
      reth: RETH,
      ysyBold: YSY,
      yBold: YBOLD,
      weth: WETH,
      usdc: USDC,
      rocketStorage: REGISTRY,
    },
    enabled: false,
    poolCutover: false,
    appendOnly: appendLocal,
    previousHead: { number: previousHead.number, hash: previousHead.hash },
    interventions: [
      "Local Anvil deployments",
      "Local Safe impersonation for vault binding",
      appendLocal
        ? "Existing Safe balance preserved; no new synthetic Safe funding"
        : "Synthetic 10 ETH Safe gas balance; NOT recovery/liquidation proceeds",
    ],
  };
  fs.writeFileSync(out, JSON.stringify(manifest, null, 2) + "\n");
  console.log(`Disabled local-only V2 fixture written to ${out}; no public deployment, cutover or funding executed.`);
}
main().catch((error) => {
  console.error(`Local fixture failed: ${error.shortMessage || error.message}`);
  process.exitCode = 1;
});
