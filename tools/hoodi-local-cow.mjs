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
if (!/^http:\/\/(127\.0\.0\.1|localhost):[0-9]+$/.test(RPC) || !['open', 'inspect', 'fill', 'finalize', 'invest-reth'].includes(ACTION) || !MANIFEST_PATH) {
  throw new Error('loopback Anvil RPC, open|inspect|fill|finalize|invest-reth and cutover manifest required');
}
if (ACTION === 'invest-reth' && !ORDER_PATH) throw new Error('settled order evidence path required');
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
for (const entry of [manifest.safe, manifest.v2.manager, manifest.v2.cowModule, manifest.v2.executor, manifest.v2.rethVault, manifest.v2.ysyBoldVault, manifest.dependencies.reth, manifest.dependencies.cowSettlement, manifest.dependencies.cowRelayer]) {
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
const rethVault = contract('RethSupporterVault', manifest.v2.rethVault.address);
const reth = new ethers.Contract(manifest.dependencies.reth.address, [
  'function balanceOf(address) view returns (uint256)',
  'function getRethValue(uint256) view returns (uint256)',
], provider);
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
  // ethers.Contract.getAddress() is a JS wrapper method; use getFunction for the Rocket Storage ABI selector.
  return registry.getFunction('getAddress')(key);
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
  const configured = await executor.limits();
  if (configured.depositPool !== limits[13] || configured.networkBalances !== limits[14] || configured.depositSettings !== limits[15]) {
    throw new Error('executor Rocket registry limits mismatch');
  }
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
} else if (ACTION === 'invest-reth') {
  const priorBytes = fs.readFileSync(ORDER_PATH, 'utf8');
  const prior = JSON.parse(priorBytes);
  if (prior.status !== 'settled' || prior.baseManifestHash !== manifestHash) throw new Error('settled order evidence mismatch');
  const current = await provider.send('eth_getBlockByNumber', ['latest', false]);
  if (Number(BigInt(current.number)) !== prior.checkpoint.blockNumber || current.hash !== prior.checkpoint.blockHash) {
    throw new Error('settled checkpoint drift');
  }
  const settlementReceipt = prior.transactions.find(record => record.label === 'manager.deployYsyProtocolPrincipal');
  if (!settlementReceipt || (await provider.getTransactionReceipt(settlementReceipt.transactionHash))?.blockHash !== settlementReceipt.blockHash) {
    throw new Error('ysy settlement receipt mismatch');
  }
  if (await cow.activeCount() || (await manager.pendingEth(2)) !== 0n || (await manager.pendingProtocolBold()) !== 0n || (await manager.pendingBold()) !== 0n) {
    throw new Error('ysy settlement or source attribution incomplete');
  }
  const ysyBucketBefore = await ysyVault.bucket(1);
  if (ysyBucketBefore.tokens !== ethers.parseEther('1000') || ysyBucketBefore.basis !== ethers.parseEther('1000')) {
    throw new Error('ysy protocol bucket mismatch');
  }
  const amount = await manager.pendingEth(1);
  if (amount === 0n || (await manager.pendingEth(0)) !== 0n || (await provider.getBalance(manifest.v2.manager.address)) !== amount) {
    throw new Error('imported rETH leg ETH custody mismatch');
  }
  const rethBucketBefore = await rethVault.bucket(1);
  if (rethBucketBefore.tokens !== 0n || rethBucketBefore.basis !== 0n || (await reth.balanceOf(manifest.v2.rethVault.address)) !== 0n) {
    throw new Error('rETH protocol bucket not empty before investment');
  }
  const limits = await executor.limits();
  const depositPool = await rocketAddress('rocketDepositPool');
  const networkBalances = await rocketAddress('rocketNetworkBalances');
  const depositSettings = await rocketAddress('rocketDAOProtocolSettingsDeposit');
  if (limits.depositPool !== depositPool || limits.networkBalances !== networkBalances || limits.depositSettings !== depositSettings) {
    throw new Error('Rocket registry changed since Safe configuration');
  }
  const settings = new ethers.Contract(depositSettings, ['function getDepositFee() view returns (uint256)'], provider);
  const pool = new ethers.Contract(depositPool, ['function getMaximumDepositAmount() view returns (uint256)'], provider);
  const fee = await settings.getDepositFee();
  if (fee > limits.maxMintFeeWad || amount > await pool.getMaximumDepositAmount()) throw new Error('Rocket fee or capacity outside test limits');
  const netEth = amount - amount * fee / 10n ** 18n;
  const previewTokens = await reth.getRethValue(netEth);
  const previewBasis = await rethVault.canonicalValue(previewTokens);
  if (previewTokens <= 1n || previewBasis <= 2n) throw new Error('real Rocket preview too small');
  const minimumTokens = previewTokens - 1n;
  const minimumBasis = previewBasis - 2n;
  await safeCall('reth.reportBounds', manifest.v2.rethVault.address, rethVault.interface.encodeFunctionData('configureReportBounds', [2 * 86400, 20000]));
  await safeCall('reth.entry', manifest.v2.rethVault.address, rethVault.interface.encodeFunctionData('configureEntry', [minimumBasis, true]));
  const beforeEth = await provider.getBalance(manifest.v2.manager.address);
  const beforeManagerReth = await reth.balanceOf(manifest.v2.manager.address);
  const beforeVaultReth = await reth.balanceOf(manifest.v2.rethVault.address);
  const deadline = (await provider.getBlock('latest')).timestamp + 60;
  const receipt = await send('manager.deployProtocolPrincipal.reth', manager.deployProtocolPrincipal(0, amount, minimumTokens, minimumBasis, deadline));
  const deployed = receipt.logs.map(log => { try { return manager.interface.parseLog(log); } catch { return null; } }).find(log => log?.name === 'ProtocolDeployed');
  if (!deployed || deployed.args.leg !== 0n || deployed.args.ethSpent !== amount) throw new Error('rETH protocol deployment event mismatch');
  const rethBucket = await rethVault.bucket(1);
  const afterManagerReth = await reth.balanceOf(manifest.v2.manager.address);
  const afterVaultReth = await reth.balanceOf(manifest.v2.rethVault.address);
  const afterExecutorReth = await reth.balanceOf(manifest.v2.executor.address);
  const afterEth = await provider.getBalance(manifest.v2.manager.address);
  const ysyBucketAfter = await ysyVault.bucket(1);
  if ((await manager.pendingEth(1)) !== 0n || afterEth !== beforeEth - amount || afterEth !== 0n ||
    rethBucket.tokens === 0n || rethBucket.basis === 0n || rethBucket.tokens < minimumTokens || rethBucket.basis < minimumBasis ||
    rethBucket.tokens !== afterVaultReth - beforeVaultReth || afterManagerReth !== beforeManagerReth || afterExecutorReth !== 0n ||
    rethBucket.basis !== await rethVault.canonicalValue(rethBucket.tokens) ||
    ysyBucketAfter.tokens !== ysyBucketBefore.tokens || ysyBucketAfter.basis !== ysyBucketBefore.basis ||
    deployed.args.tokens !== rethBucket.tokens || deployed.args.basis !== rethBucket.basis) {
    throw new Error('rETH/Ysy protocol bucket, ETH liability or custody reconciliation failed');
  }
  evidence = {
    ...prior,
    status: 'both-invested',
    previousEvidenceHash: ethers.keccak256(ethers.toUtf8Bytes(priorBytes)),
    rethInvestment: {
      kind: 'real-hoodi-rocket-pool',
      depositPool,
      depositPoolCodeHash: ethers.keccak256(await provider.getCode(depositPool)),
      ethInWei: amount.toString(),
      feeWad: fee.toString(),
      minimumRethWei: minimumTokens.toString(),
      minimumBasisEthWei: minimumBasis.toString(),
      receivedRethWei: rethBucket.tokens.toString(),
      basisEthWei: rethBucket.basis.toString(),
      vaultRethBalanceWei: afterVaultReth.toString(),
      managerEthBeforeWei: beforeEth.toString(),
      managerEthAfterWei: afterEth.toString(),
      pendingRethEthAfterWei: (await manager.pendingEth(1)).toString(),
      ysyProtocolTokensWei: ysyBucketAfter.tokens.toString(),
      ysyProtocolBasisWei: ysyBucketAfter.basis.toString(),
    },
    transactions: [...prior.transactions, ...records],
  };
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
