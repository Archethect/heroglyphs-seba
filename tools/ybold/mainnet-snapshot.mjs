import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

// Read-only inventory: no signer, transaction submission, or AWS access.
const rpc = process.env.MAINNET_RPC;
const output = process.argv[2];
if (!rpc || !output) throw new Error("Set MAINNET_RPC; pass the output JSON path");
let requestId = 0;
async function request(method, params) {
  const response = await fetch(rpc, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++requestId, method, params }),
    signal: AbortSignal.timeout(20000),
  });
  if (!response.ok) throw new Error(`RPC HTTP ${response.status}`);
  const body = await response.json();
  if (body.error) throw new Error(`RPC ${body.error.code}: ${body.error.message}`);
  return body.result;
}
const abi = (...args) => execFileSync("cast", args, { encoding: "utf8" }).trim();
const block = await request("eth_getBlockByNumber", [process.env.YBOLD_SNAPSHOT_BLOCK || "latest", false]);
const pin = block.number;
async function call(target, signature, args = []) {
  const input = signature.slice(0, signature.indexOf(")") + 1);
  const data = abi("calldata", input, ...args.map(String));
  const raw = await request("eth_call", [{ to: target, data }, pin]);
  return abi("abi-decode", signature, raw);
}
const A = {
  manager: "0xCAd999958e9619C3E5Bed96B8725Bb0b0fa45269",
  pool: "0xe3B17b4533b339d3CBC26F57199d3fb937129894",
  beefy: "0x87Be53F4E45f3EAFa4b8f2dD8B852115Bb1f16Ba",
  treasury: "0x888D768764A2E304215247F0bA3457cCb0f0ab4f",
  governance: "0xf83b11b09EEc073ACE4481b2F4c8357e156714b3",
  governanceAdminPlugin: "0xef639bdd87805e811b3c5d3e308d3300561cb4d6",
  governanceMultisigPlugin: "0x5373e070a37a51a400c98df4087753ecdd98f57d",
  governanceAdminMember: "0x5ebaaa3e84f9595fbf787a71c3caad97d370bc28",
  bold: "0x6440f144b7e50D6a8439336510312d2F54beB01D",
  yBold: "0x9F4330700a36B29952869fac9b33f45EEdd8A3d8",
  stYBold: "0x23346B04a7f55b8760E5860AA5A77383D63491cD",
  curve: "0xEFc6516323FbD28e80B85A497B65A86243a54B3E",
  weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
  usdc: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  ethFeed: "0xc0053f3FBcCD593758258334Dfce24C2A9A673aD",
  usdcFeed: "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6",
};
const snapshot = {
  observedAt: new Date().toISOString(),
  block: Number(BigInt(pin)),
  hash: block.hash,
  timestamp: Number(BigInt(block.timestamp)),
  chainId: await request("eth_chainId", []),
  addresses: A,
  reads: {},
};
const daoExecute = abi("keccak", "EXECUTE_PERMISSION");
const checks = [
  [
    "governance.adminPluginExecutes",
    A.governance,
    "hasPermission(address,address,bytes32,bytes)(bool)",
    [A.governance, A.governanceAdminPlugin, daoExecute, "0x"],
  ],
  [
    "governance.multisigExecutes",
    A.governance,
    "hasPermission(address,address,bytes32,bytes)(bool)",
    [A.governance, A.governanceMultisigPlugin, daoExecute, "0x"],
  ],
  [
    "governance.treasuryDirectExecutes",
    A.governance,
    "hasPermission(address,address,bytes32,bytes)(bool)",
    [A.governance, A.treasury, daoExecute, "0x"],
  ],
  ["governance.adminMember", A.governanceAdminPlugin, "isMember(address)(bool)", [A.governanceAdminMember]],
  ["governance.treasuryAdminMember", A.governanceAdminPlugin, "isMember(address)(bool)", [A.treasury]],
  ["governance.multisigSettings", A.governanceMultisigPlugin, "multisigSettings()(bool,uint16)"],
  ["governance.adminTarget", A.governanceAdminPlugin, "getTargetConfig()((address,uint8))"],
  ["governance.multisigTarget", A.governanceMultisigPlugin, "getTargetConfig()((address,uint8))"],
  ["manager.yieldVault", A.manager, "yieldVault()(address)"],
  ["manager.principalValue", A.manager, "principalValue()(uint256)"],
  ["manager.depositId", A.manager, "depositId()(uint256)"],
  ["manager.pendingBoldConversion", A.manager, "pendingBoldConversion()(uint256)"],
  ["manager.activeRouterUid", A.manager, "activeRouterUid()(bytes32)"],
  ["manager.yieldFlowActive", A.manager, "yieldFlowActive()(bool)"],
  ["beefy.principalValue", A.beefy, "principalValue()(uint256)"],
  ["beefy.principalShares", A.beefy, "principalShares()(uint256)"],
  ["yBold.asset", A.yBold, "asset()(address)"],
  ["yBold.symbol", A.yBold, "symbol()(string)"],
  ["yBold.shutdown", A.yBold, "isShutdown()(bool)"],
  ["yBold.totalAssets", A.yBold, "totalAssets()(uint256)"],
  ["yBold.maxDeposit", A.yBold, "maxDeposit(address)(uint256)", [A.manager]],
  ["stYBold.asset", A.stYBold, "asset()(address)"],
  ["stYBold.symbol", A.stYBold, "symbol()(string)"],
  ["stYBold.shutdown", A.stYBold, "isShutdown()(bool)"],
  ["stYBold.totalAssets", A.stYBold, "totalAssets()(uint256)"],
  ["stYBold.maxDeposit", A.stYBold, "maxDeposit(address)(uint256)", [A.manager]],
  ["curve.coins0", A.curve, "coins(uint256)(address)", [0]],
  ["curve.coins1", A.curve, "coins(uint256)(address)", [1]],
  ["curve.balance0", A.curve, "balances(uint256)(uint256)", [0]],
  ["curve.balance1", A.curve, "balances(uint256)(uint256)", [1]],
  ["curve.ema", A.curve, "price_oracle(uint256)(uint256)", [0]],
  ["ethFeed.round", A.ethFeed, "latestRoundData()(uint80,int256,uint256,uint256,uint80)"],
  ["ethFeed.description", A.ethFeed, "description()(string)"],
  ["usdcFeed.description", A.usdcFeed, "description()(string)"],
  ["usdcFeed.round", A.usdcFeed, "latestRoundData()(uint80,int256,uint256,uint256,uint80)"],
  ["treasury.threshold", A.treasury, "getThreshold()(uint256)"],
  ["treasury.owners", A.treasury, "getOwners()(address[])"],
  [
    "treasury.modules",
    A.treasury,
    "getModulesPaginated(address,uint256)(address[],address)",
    ["0x0000000000000000000000000000000000000001", 32],
  ],
  [
    "treasury.guard",
    A.treasury,
    "getStorageAt(uint256,uint256)(bytes)",
    ["0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8", 1],
  ],
  ["governance.threshold", A.governance, "getThreshold()(uint256)"],
  ["governance.owners", A.governance, "getOwners()(address[])"],
];
for (const [label, target, signature, args] of checks) {
  try {
    snapshot.reads[label] = await call(target, signature, args);
  } catch (error) {
    snapshot.reads[label] = { error: error.message };
  }
}
snapshot.deposits = [];
const count = Number(String(snapshot.reads["manager.depositId"]).split(" ")[0]);
if (!Number.isSafeInteger(count) || count > 10000) throw new Error("Unexpected deposit count");
for (let id = 1; id <= count; id++)
  snapshot.deposits.push({
    id,
    record: await call(A.manager, "deposits(uint256)(address,address,uint256,uint32)", [id]),
  });
snapshot.balances = {};
for (const label of ["treasury", "manager", "governance"]) {
  snapshot.balances[`${label}.ETH`] = BigInt(await request("eth_getBalance", [A[label], pin])).toString();
  for (const token of ["usdc", "weth", "bold", "yBold", "stYBold"])
    snapshot.balances[`${label}.${token}`] = await call(A[token], "balanceOf(address)(uint256)", [A[label]]);
}
const role = abi("keccak", "ADMIN_ROLE");
snapshot.roles = {};
snapshot.roles["governanceAdminMember.codeBytes"] =
  ((await request("eth_getCode", [A.governanceAdminMember, pin])).length - 2) / 2;
snapshot.implementations = {};
for (const label of ["governance", "governanceMultisigPlugin"])
  snapshot.implementations[label] = await request("eth_getStorageAt", [
    A[label],
    "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc",
    pin,
  ]);
for (const label of ["treasury", "governance"]) {
  snapshot.roles[`${label}.managerAdmin`] = await call(A.manager, "hasRole(bytes32,address)(bool)", [role, A[label]]);
  snapshot.roles[`${label}.codeBytes`] = ((await request("eth_getCode", [A[label], pin])).length - 2) / 2;
}
mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, `${JSON.stringify(snapshot, null, 2)}\n`);
console.log(JSON.stringify(snapshot, null, 2));
