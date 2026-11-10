// Synthetic CoW lifecycle on an already-cut-over local Anvil Hoodi fork only.
import fs from 'node:fs';
import path from 'node:path';
import { ethers } from 'ethers';

const RPC = process.env.HOODI_LOCAL_RPC ?? 'http://127.0.0.1:8547';
const ACTION = process.argv[2];
const MANIFEST_PATH = process.argv[3];
const ORDER_PATH = process.argv[4];
const OWNER = '0x00008A88A21a1d34CDDAA7fC15A0E84ed7e42D8f';
const ANCHOR = 3_988_379;
if (!/^http:\/\/(127\.0\.0\.1|localhost):[0-9]+$/.test(RPC) || !['open', 'inspect', 'fill', 'finalize'].includes(ACTION) || !MANIFEST_PATH) {
  throw new Error('loopback Anvil RPC, open|inspect|fill|finalize and cutover manifest required');
}
const provider = new ethers.JsonRpcProvider(RPC);
const info = await provider.send('anvil_nodeInfo', []);
if (Number(info.forkConfig?.forkBlockNumber) !== ANCHOR || (await provider.getNetwork()).chainId !== 560048n) {
  throw new Error('wrong Anvil Hoodi fork');
}
const manifestBytes = fs.readFileSync(MANIFEST_PATH, 'utf8');
const manifest = JSON.parse(manifestBytes);
if (manifest.phase !== 'cutover' || manifest.mode !== 'isolated-mock-backed' || manifest.testOnly !== true) {
  throw new Error('cutover manifest required');
}
const manifestHash = ethers.keccak256(ethers.toUtf8Bytes(manifestBytes));
const pool = new ethers.Contract(manifest.v1.pool.address, ['function yieldManager() view returns (address)'], provider);
if ((await pool.yieldManager()) !== manifest.v2.manager.address) throw new Error('pool pointer drift');
for (const entry of [manifest.safe, manifest.v2.manager, manifest.v2.cowModule, manifest.dependencies.cowSettlement, manifest.dependencies.cowRelayer]) {
  if (ethers.keccak256(await provider.getCode(entry.address)) !== entry.runtimeCodeHash) throw new Error('codehash drift');
}
if ((await provider.getBlock(manifest.checkpoint.blockNumber)).hash !== manifest.checkpoint.blockHash) {
  throw new Error('cutover checkpoint missing');
}
await provider.send('anvil_impersonateAccount', [OWNER]);
const signer = await provider.getSigner(OWNER);
function artifact(name, file = name) {
  return JSON.parse(fs.readFileSync(path.resolve(`out/${file}.sol/${name}.json`), 'utf8'));
}
function contract(name, address, file = name) {
  return new ethers.Contract(address, artifact(name, file).abi, signer);
}
const manager = contract('YieldManagerV2', manifest.v2.manager.address);
const cow = contract('SebaCowIntentModule', manifest.v2.cowModule.address);
const executor = contract('SebaV2DirectExecutor', manifest.v2.executor.address);
const settlement = contract('HoodiCowSettlementMock', manifest.dependencies.cowSettlement.address, 'HoodiExternalMocks');
const ysyVault = contract('YsyBoldSupporterVault', manifest.v2.ysyBoldVault.address);
const safeAbi = [
  'function nonce() view returns (uint256)',
  'function approveHash(bytes32)',
  'function getTransactionHash(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,uint256) view returns (bytes32)',
  'function execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes) returns (bool)',
  'event ExecutionSuccess(bytes32 indexed txHash,uint256 payment)',
];
const safe = new ethers.Contract(manifest.safe.address, safeAbi, signer);
const records = [];
async function send(label, request) {
  const receipt = await (await request).wait();
  if (receipt.status !== 1) throw new Error(`${label} reverted`);
  records.push({ label, transactionHash: receipt.hash, blockNumber: receipt.blockNumber, blockHash: receipt.blockHash });
  return receipt;
}
async function safeCall(label, target, data) {
  const hash = await safe.getTransactionHash(target, 0, data, 0, 0, 0, 0, ethers.ZeroAddress, ethers.ZeroAddress, await safe.nonce());
  await send(`approve.${label}`, safe.approveHash(hash));
  const sig = ethers.concat([ethers.zeroPadValue(OWNER, 32), ethers.ZeroHash, '0x01']);
  const receipt = await send(`execute.${label}`, safe.execTransaction(target, 0, data, 0, 0, 0, 0, ethers.ZeroAddress, ethers.ZeroAddress, sig));
  const topic = ethers.id('ExecutionSuccess(bytes32,uint256)');
  if (!receipt.logs.some(log => log.address.toLowerCase() === manifest.safe.address.toLowerCase() && log.topics[0] === topic)) {
    throw new Error(`Safe call ${label} failed`);
  }
}
function rocketAddress(name) {
  const key = ethers.keccak256(ethers.solidityPacked(['string', 'string'], ['contract.address', name]));
  return registry.getAddress(key);
}
const registry = new ethers.Contract(manifest.dependencies.rocketStorage.address, ['function getAddress(bytes32) view returns (address)'], provider);
let evidence;
if (ACTION === 'open') {
  if ((await manager.pendingEth(2)) === 0n || await manager.executionEnabled() || await cow.enabled()) {
    throw new Error('expected disabled V2 ysy protocol capital');
  }
  const limits = [
    ethers.parseEther('10'), ethers.parseEther('10'), ethers.parseEther('2000'), 10n ** 15n,
    0, 0, 2 * 86400, 20000, 900, 0, 0, 0, 0,
    await rocketAddress('rocketDepositPool'),
    await rocketAddress('rocketNetworkBalances'),
    await rocketAddress('rocketDAOProtocolSettingsDeposit'),
  ];
  await safeCall('executor.limits', manifest.v2.executor.address, executor.interface.encodeFunctionData('configureLimits', [limits]));
  await safeCall('executor.boldLimit', manifest.v2.executor.address, executor.interface.encodeFunctionData('configureBoldLimit', [ethers.parseEther('2000')]));
  await safeCall('executor.enable', manifest.v2.executor.address, executor.interface.encodeFunctionData('setEnabled', [true]));
  await safeCall('cow.limits', manifest.v2.cowModule.address, cow.interface.encodeFunctionData('configureLimits', [ethers.parseEther('10'), ethers.parseEther('10'), 86400]));
  await safeCall('cow.enable', manifest.v2.cowModule.address, cow.interface.encodeFunctionData('setEnabled', [true]));
  await safeCall('ysy.entry', manifest.v2.ysyBoldVault.address, ysyVault.interface.encodeFunctionData('configureEntry', [1, true]));
  await safeCall('manager.operator', manifest.v2.manager.address, manager.interface.encodeFunctionData('setOperator', [OWNER, true]));
  await safeCall('manager.execution', manifest.v2.manager.address, manager.interface.encodeFunctionData('setExecutionEnabled', [true]));
  const amount = await manager.pendingEth(2);
  const block = await provider.getBlock('latest');
  const orderId = await cow.nextOrderId();
  await send('manager.openCowOrder', manager.openCowOrder(1, amount, ethers.parseEther('900'), block.timestamp + 86400, orderId, ethers.zeroPadValue('0x01', 32)));
  const order = await cow.order(orderId);
  evidence = {
    schemaVersion: 'seba-hoodi-local-cow-evidence-v1', mode: 'synthetic-venue', chainId: 560048,
    baseManifestHash: manifestHash, status: 'pending', orderId: orderId.toString(), escrow: order.escrow,
    uid: await cow.orderUid(orderId), sellAmountWei: amount.toString(), expectedMinimumBold: ethers.parseEther('900').toString(),
    transactions: records,
  };
} else if (ACTION === 'inspect') {
  if (!ORDER_PATH) throw new Error('pending order evidence path required');
  const pending = JSON.parse(fs.readFileSync(ORDER_PATH, 'utf8'));
  if (pending.status !== 'pending' || pending.baseManifestHash !== manifestHash) throw new Error('pending order evidence mismatch');
  const order = await cow.order(pending.orderId);
  if (order.escrow !== pending.escrow || (await cow.orderUid(pending.orderId)) !== pending.uid || order.closed) throw new Error('order state drift');
  const opened = pending.transactions.find(record => record.label === 'manager.openCowOrder');
  if (!opened || (await provider.getTransactionReceipt(opened.transactionHash))?.blockHash !== opened.blockHash) throw new Error('open receipt mismatch');
  evidence = pending;
} else {
  if (!ORDER_PATH) throw new Error('order evidence path required');
  const prior = JSON.parse(fs.readFileSync(ORDER_PATH, 'utf8'));
  const expectedStatus = ACTION === 'fill' ? 'pending' : 'ready';
  if (prior.status !== expectedStatus || prior.baseManifestHash !== manifestHash) throw new Error('order evidence status mismatch');
  const order = await cow.order(prior.orderId);
  if (order.escrow !== prior.escrow || (await cow.orderUid(prior.orderId)) !== prior.uid || order.closed) throw new Error('order state drift');
  if (ACTION === 'fill') {
    await send('mock.syntheticSettlement', settlement.settleMockOrder(order.escrow, ethers.parseEther('1000')));
    if ((await provider.getCode(order.escrow)) === '0x') throw new Error('escrow disappeared');
    evidence = { ...prior, status: 'ready', transactions: [...prior.transactions, ...records] };
  } else {
    await send('manager.finalizeCowOrder', manager.finalizeCowOrder(prior.orderId));
    if ((await manager.pendingProtocolBold()) !== ethers.parseEther('1000') || (await manager.pendingBold()) !== 0n) throw new Error('source attribution drift');
    await send('manager.deployYsyProtocolPrincipal', manager.deployYsyProtocolPrincipal(ethers.parseEther('1000'), 1, 1, (await provider.getBlock('latest')).timestamp + 60));
    evidence = { ...prior, status: 'settled', transactions: [...prior.transactions, ...records] };
  }
}
const latest = await provider.send('eth_getBlockByNumber', ['latest', false]);
evidence.checkpoint = { blockNumber: Number(BigInt(latest.number)), blockHash: latest.hash };
if (evidence.checkpoint.blockNumber < Math.max(...evidence.transactions.map(record => record.blockNumber))) {
  throw new Error('checkpoint predates an operation receipt');
}
const output = `${JSON.stringify(evidence, null, 2)}\n`;
const hash = ethers.keccak256(ethers.toUtf8Bytes(output));
const file = path.resolve(`broadcast/hoodi-local/cow-${evidence.status}-${hash.slice(2, 18)}.json`);
fs.writeFileSync(file, output, { flag: 'wx' });
console.log(JSON.stringify({ status: evidence.status, evidence: file, hash, orderId: evidence.orderId, escrow: evidence.escrow, uid: evidence.uid, checkpoint: evidence.checkpoint }));
