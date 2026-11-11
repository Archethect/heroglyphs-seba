// Deterministic, signer-free V1 Hoodi deployment plan. Never sends transactions.
import fs from "node:fs";
import path from "node:path";
import { ethers } from "ethers";
import { create2Deployment, multiSendData } from "./hoodi-safe-createcall.mjs";
import { SAFE_MULTISEND } from "./hoodi-public-safe-plan.mjs";

function artifact(name, file = name) {
  const raw = JSON.parse(fs.readFileSync(path.resolve(`out/${file}.sol/${name}.json`), "utf8"));
  if (!raw.bytecode?.object || !ethers.isHexString(raw.bytecode.object)) {
    throw new Error(`missing compiled ${name} artifact`);
  }
  return raw;
}

function batch(name, calls) {
  return {
    name,
    calls,
    transaction: { to: SAFE_MULTISEND, valueWei: "0", operation: 1, data: multiSendData(calls) },
  };
}

export async function buildHoodiV1Plan(safe, owner) {
  if (!ethers.isAddress(safe) || safe === ethers.ZeroAddress) throw new Error("Safe address required");
  if (!ethers.isAddress(owner) || owner === ethers.ZeroAddress) throw new Error("owner address required");
  const entries = [];
  const add = async (name, constructorArgs = [], file = name, label = name) => {
    const a = artifact(name, file);
    const creationCode = (
      await new ethers.ContractFactory(a.abi, a.bytecode.object).getDeployTransaction(...constructorArgs)
    ).data;
    if (!creationCode) throw new Error(`no creation code for ${name}`);
    const salt = ethers.id(`seba:hoodi:560048:v1:${safe}:${label}`);
    const call = create2Deployment(creationCode, salt);
    const entry = {
      name,
      label,
      file,
      constructorArgs,
      to: call.to,
      valueWei: "0",
      data: call.data,
      salt,
      expectedAddress: call.expectedAddress,
      creationCode,
      creationCodeHash: ethers.keccak256(creationCode),
    };
    entries.push(entry);
    return entry.expectedAddress;
  };

  const weth = await add("MockWETH");
  const usdc = await add("MockUSDC");
  const bold = await add("MockBold");
  const sBold = await add("HoodiSBoldMock", [bold], "HoodiExternalMocks");
  const ethFeed = await add("HoodiPriceFeedMock", [2000n * 10n ** 8n, safe], "HoodiExternalMocks", "ethUsdFeed");
  const usdcFeed = await add("HoodiPriceFeedMock", [10n ** 8n, safe], "HoodiExternalMocks", "usdcUsdFeed");
  const uniswap = await add("HoodiUniswapMock", [weth, usdc], "HoodiExternalMocks");
  const curve = await add("HoodiCurveMock", [usdc], "HoodiExternalMocks");
  const beefy = await add("HoodiBeefyMock", [curve], "HoodiExternalMocks");
  await add("HoodiBeefyHarvesterMock", [], "HoodiExternalMocks");
  const ethFlow = await add("HoodiEthFlowMock", [owner], "HoodiExternalMocks");
  const router = await add("EthToBoldRouter", [ethFlow, bold, safe, safe]);
  const pyb = await add("PYBSeba", [safe, sBold]);
  const pool = await add("SebaPool", [safe, owner]);
  const adapter = await add("EUSDUSDCBeefyYieldVault", [
    safe,
    safe,
    weth,
    usdc,
    uniswap,
    uniswap,
    curve,
    beefy,
    ethFeed,
    usdcFeed,
  ]);
  const manager = await add("YieldManager", [safe, owner, pool, router, bold, sBold, pyb, adapter]);
  await add("RocketPoolBackPay", [pool]);

  const adapterAbi = new ethers.Interface(artifact("EUSDUSDCBeefyYieldVault").abi);
  const routerAbi = new ethers.Interface(artifact("EthToBoldRouter").abi);
  const pybAbi = new ethers.Interface(artifact("PYBSeba").abi);
  const poolAbi = new ethers.Interface(artifact("SebaPool").abi);
  const adapterRole = ethers.id("YIELDMANAGER_ROLE");
  const routerRole = ethers.id("YIELD_MANAGER_ROLE");
  const bindings = [
    {
      label: "adapter.grantManager",
      to: adapter,
      data: adapterAbi.encodeFunctionData("grantRole", [adapterRole, manager]),
    },
    {
      label: "adapter.revokeBootstrapSafeManager",
      to: adapter,
      data: adapterAbi.encodeFunctionData("revokeRole", [adapterRole, safe]),
    },
    { label: "pyb.bindPool", to: pyb, data: pybAbi.encodeFunctionData("setSebaPool", [pool]) },
    { label: "pool.bindPyb", to: pool, data: poolAbi.encodeFunctionData("setSebaVault", [pyb]) },
    { label: "pool.bindManager", to: pool, data: poolAbi.encodeFunctionData("setYieldManager", [manager]) },
    {
      label: "router.grantManager",
      to: router,
      data: routerAbi.encodeFunctionData("grantRole", [routerRole, manager]),
    },
    {
      label: "router.revokeBootstrapSafeManager",
      to: router,
      data: routerAbi.encodeFunctionData("revokeRole", [routerRole, safe]),
    },
  ];
  return {
    schemaVersion: "seba-hoodi-public-v1-plan-v1",
    chainId: 560048,
    network: "hoodi",
    readOnly: true,
    broadcast: false,
    safe,
    owner,
    deployments: entries,
    bindings,
    batches: [
      batch("dependencies-a", entries.slice(0, 6)),
      batch("dependencies-b", entries.slice(6, 11)),
      batch("core-a", entries.slice(11, 14)),
      batch("core-b", entries.slice(14, 17)),
      batch("bindings", bindings),
    ],
  };
}
