// Deterministic, signer-free Hoodi V2 staging plan. Never sends transactions.
import fs from "node:fs";
import path from "node:path";
import { ethers } from "ethers";
import { create2Deployment, multiSendData } from "./hoodi-safe-createcall.mjs";
import { SAFE_MULTISEND, HOODI_ADMIN } from "./hoodi-public-safe-plan.mjs";
import { HOODI_REHEARSAL_SAFE } from "./hoodi-public-v1-next.mjs";

function artifact(name, file = name) {
  const raw = JSON.parse(fs.readFileSync(path.resolve(`out/${file}.sol/${name}.json`), "utf8"));
  if (!raw.bytecode?.object || !ethers.isHexString(raw.bytecode.object)) {
    throw new Error(`missing compiled ${name} artifact`);
  }
  return raw;
}

function address(entry) {
  if (!entry || !ethers.isAddress(entry.address) || entry.address === ethers.ZeroAddress) {
    throw new Error("V1 evidence missing required contract address");
  }
  return ethers.getAddress(entry.address);
}

function requireV1Manifest(m) {
  if (
    m?.schemaVersion !== "seba-hoodi-rehearsal-v1" ||
    m.network !== "hoodi" ||
    m.chainId !== 560048 ||
    m.testOnly !== true ||
    m.mode !== "isolated-mock-backed" ||
    m.phase !== "v1-ready" ||
    m.safe?.address !== HOODI_REHEARSAL_SAFE ||
    m.safe?.threshold !== 1 ||
    m.safe?.owners?.length !== 1 ||
    m.safe.owners[0] !== HOODI_ADMIN
  ) throw new Error("unapproved Hoodi V1 evidence");
  for (const [section, key] of [
    ["v1", "pool"], ["v1", "pybSeba"], ["v1", "sBold"],
    ["dependencies", "bold"], ["dependencies", "weth"],
    ["dependencies", "reth"], ["dependencies", "rocketStorage"],
  ]) address(m[section]?.[key]);
}

function batch(name, calls) {
  return {
    name,
    calls,
    transaction: { to: SAFE_MULTISEND, valueWei: "0", operation: 1, data: multiSendData(calls) },
  };
}

export async function buildHoodiV2StagePlan(v1Manifest) {
  requireV1Manifest(v1Manifest);
  const safe = HOODI_REHEARSAL_SAFE;
  const owner = HOODI_ADMIN;
  const v1 = v1Manifest.v1;
  const d = v1Manifest.dependencies;
  const entries = [];
  const add = async (name, constructorArgs = [], file = name, label = name) => {
    const a = artifact(name, file);
    const creationCode = (
      await new ethers.ContractFactory(a.abi, a.bytecode.object).getDeployTransaction(...constructorArgs)
    ).data;
    if (!creationCode) throw new Error(`no creation code for ${name}`);
    const salt = ethers.id(`seba:hoodi:560048:v2:${safe}:${label}`);
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

  const yBold = await add("HoodiYearnMock", [address(d.bold), "Hoodi mock yBOLD", "hyBOLD"], "HoodiExternalMocks", "yBold");
  const ysyBold = await add("HoodiYearnMock", [yBold, "Hoodi mock ysyBOLD", "hysyBOLD"], "HoodiExternalMocks", "ysyBold");
  const managerImplementation = await add("YieldManagerV2", [], "YieldManagerV2", "managerImplementation");
  const managerInit = new ethers.Interface(artifact("YieldManagerV2").abi).encodeFunctionData("initialize", [[
    safe, ethers.ZeroAddress, address(v1.pool), address(d.bold), address(v1.sBold),
    address(v1.pybSeba), address(d.reth), ysyBold,
  ]]);
  const manager = await add("ERC1967Proxy", [managerImplementation, managerInit], "ERC1967Proxy", "managerProxy");
  const rethImplementation = await add("RethSupporterVault", [], "RethSupporterVault", "rethImplementation");
  const rethInit = new ethers.Interface(artifact("RethSupporterVault").abi).encodeFunctionData("initialize", [
    safe, manager, address(d.reth), address(d.rocketStorage),
  ]);
  const rethVault = await add("ERC1967Proxy", [rethImplementation, rethInit], "ERC1967Proxy", "rethProxy");
  const ysyBoldImplementation = await add("YsyBoldSupporterVault", [], "YsyBoldSupporterVault", "ysyBoldImplementation");
  const ysyInit = new ethers.Interface(artifact("YsyBoldSupporterVault").abi).encodeFunctionData("initialize", [
    safe, manager, ysyBold, yBold,
  ]);
  const ysyBoldVault = await add("ERC1967Proxy", [ysyBoldImplementation, ysyInit], "ERC1967Proxy", "ysyBoldProxy");
  const executor = await add("SebaV2DirectExecutor", [[
    manager, safe, address(d.reth), address(d.weth), ethers.ZeroAddress, address(d.bold),
    yBold, ysyBold, ethers.ZeroAddress, ethers.ZeroAddress, ethers.ZeroAddress,
    ethers.ZeroAddress, address(d.rocketStorage),
  ]]);
  const cowSettlement = await add("HoodiCowSettlementMock", [address(d.bold), owner], "HoodiExternalMocks", "cowSettlement");
  const cowModule = await add("SebaCowIntentModule", [
    manager, safe, address(d.weth), address(d.reth), address(d.bold), cowSettlement,
  ], "SebaCowIntentModule", "cowModule");

  const managerAbi = new ethers.Interface(artifact("YieldManagerV2").abi);
  const bindings = [
    { label: "manager.bindVaults", to: manager, data: managerAbi.encodeFunctionData("bindVaults", [rethVault, ysyBoldVault]) },
    {
      label: "manager.configureDisabledExecutor", to: manager,
      data: managerAbi.encodeFunctionData("configureExecution", [executor, ethers.parseEther("10"), ethers.parseEther("10"), ethers.parseEther("10")]),
    },
    { label: "manager.configureDisabledCow", to: manager, data: managerAbi.encodeFunctionData("configureCowModule", [cowModule]) },
  ];
  return {
    schemaVersion: "seba-hoodi-public-v2-stage-plan-v1",
    chainId: 560048,
    network: "hoodi",
    readOnly: true,
    broadcast: false,
    safe,
    owner,
    addresses: { yBold, ysyBold, manager, rethVault, ysyBoldVault, executor, cowSettlement, cowModule },
    deployments: entries,
    bindings,
    batches: [
      batch("yearn-mocks", entries.slice(0, 2)),
      batch("manager", entries.slice(2, 4)),
      batch("reth-vault", entries.slice(4, 6)),
      batch("ysybold-vault", entries.slice(6, 8)),
      batch("executor-and-cow", entries.slice(8, 11)),
      batch("disabled-bindings", bindings),
    ],
  };
}
