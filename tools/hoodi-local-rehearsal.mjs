// Local receipt producer only. Never run against a public RPC endpoint.
import fs from 'node:fs';
import path from 'node:path';
import { ethers } from 'ethers';
import { assertSourceLineage, currentSource } from './hoodi-source-gate.mjs';

const RPC = process.env.HOODI_LOCAL_RPC ?? 'http://127.0.0.1:8547';
const PHASE = process.argv[2];
const INPUT = process.argv[3];
const ANCHOR = 3_988_379;
const OWNER = '0x00008A88A21a1d34CDDAA7fC15A0E84ed7e42D8f';
const SINGLETON = '0x41675C099F32341bf84BFc5382aF534df5C7461a';
const FACTORY = '0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67';
const MULTISEND = '0x38869bf66a61cF6bDB996A6aE40D5853Fd43B526';
const RETH = '0x7322c24752f79c05FFD1E2a6FCB97020C1C264F1';
const REGISTRY = '0x594Fb75D3dc2DFa0150Ad03F99F97817747dd4E1';
const GUARD_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8n;
const ALLOWED = ['v1', 'v2', 'stage-a', 'stage-b'];

if (!/^http:\/\/(127\.0\.0\.1|localhost):[0-9]+$/.test(RPC)) throw new Error('Local loopback RPC required');
if (!ALLOWED.includes(PHASE)) throw new Error(`phase must be ${ALLOWED.join(', ')}`);
if (PHASE !== 'v1' && !INPUT) throw new Error('previous immutable manifest path required');

const provider = new ethers.JsonRpcProvider(RPC);
const nodeInfo = await provider.send('anvil_nodeInfo', []);
if (Number(nodeInfo.forkConfig?.forkBlockNumber) !== ANCHOR) throw new Error('wrong Anvil fork anchor');
const network = await provider.getNetwork();
if (network.chainId !== 560048n) throw new Error('wrong chain');
const anchorBlock = await provider.getBlock(ANCHOR);
if (!anchorBlock?.hash) throw new Error('missing anchor block');
await provider.send('anvil_impersonateAccount', [OWNER]);
const signer = await provider.getSigner(OWNER);

function art(name, file = name) {
  const filePath = path.resolve(`out/${file}.sol/${name}.json`);
  const raw = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  if (!raw.bytecode?.object || raw.bytecode.object === '0x') throw new Error(`missing forge artifact ${filePath}`);
  return raw;
}
function contract(name, address, file = name) {
  return new ethers.Contract(address, art(name, file).abi, signer);
}
function evidence(receipt) {
  return {
    transactionHash: receipt.hash,
    blockNumber: receipt.blockNumber,
    blockHash: receipt.blockHash,
  };
}
function clean(value) {
  return JSON.parse(JSON.stringify(value, (_, item) => typeof item === 'bigint' ? item.toString() : item));
}
const previous = INPUT ? JSON.parse(fs.readFileSync(INPUT, 'utf8')) : undefined;
const previousText = INPUT ? fs.readFileSync(INPUT, 'utf8') : undefined;
if (previous && (previous.chainId !== 560048 || previous.network !== 'hoodi' || previous.testOnly !== true)) {
  throw new Error('previous manifest is not the Hoodi test-only schema');
}
const source = currentSource();
const m = previous ?? {
  schemaVersion: 'seba-hoodi-rehearsal-v1',
  network: 'hoodi',
  chainId: 560048,
  testOnly: true,
  mode: 'isolated-mock-backed',
  source,
  anchor: { blockNumber: ANCHOR, blockHash: anchorBlock.hash },
  safe: {}, dependencies: {}, v1: {}, v2: {}, cutover: {}, reconciliation: {}, transactions: [],
};
if (m.schemaVersion !== 'seba-hoodi-rehearsal-v1' || m.mode !== 'isolated-mock-backed' || m.anchor.blockHash !== anchorBlock.hash) {
  throw new Error('manifest schema or fork anchor mismatch');
}
if (previous) m.previousManifestHash = ethers.keccak256(ethers.toUtf8Bytes(previousText));

if (previous) {
  assertSourceLineage(previous.source, source);
  const current = await provider.getBlock('latest');
  if (current.number !== previous.checkpoint.blockNumber || current.hash !== previous.checkpoint.blockHash) {
    throw new Error('Anvil state advanced or reset since previous manifest');
  }
  for (const group of [previous.safe, previous.dependencies, previous.v1, previous.v2]) {
    for (const entry of Object.values(group)) {
      if (!entry || typeof entry !== 'object' || !entry.address) continue;
      const code = await provider.getCode(entry.address);
      if (code === '0x' || ethers.keccak256(code) !== entry.runtimeCodeHash) throw new Error(`codehash drift: ${entry.address}`);
      const checkpoint = entry.evidence ?? entry.verifiedAt;
      if (!checkpoint || (await provider.getBlock(checkpoint.blockNumber))?.hash !== checkpoint.blockHash) {
        throw new Error(`receipt/verification block mismatch: ${entry.address}`);
      }
      if (entry.evidence && (await provider.getTransactionReceipt(entry.evidence.transactionHash))?.blockHash !== checkpoint.blockHash) {
        throw new Error(`deployment receipt mismatch: ${entry.address}`);
      }
    }
  }
  const pool = new ethers.Contract(previous.v1.pool.address, ['function yieldManager() view returns (address)'], provider);
  if ((await pool.yieldManager()) !== previous.v1.manager.address) throw new Error('unexpected pool pointer before cutover');
  const old = new ethers.Contract(previous.v1.manager.address, [
    'function yieldVault() view returns (address)',
    'function depositId() view returns (uint256)',
    'function pendingBoldConversion() view returns (uint256)',
  ], provider);
  if (previous.phase === 'v1-ready' || previous.phase === 'v2-staged') {
    if ((await old.yieldVault()) !== previous.v1.beefyAdapter.address || (await old.depositId()) !== 0n || (await old.pendingBoldConversion()) !== 0n) {
      throw new Error('V1 exit preconditions changed');
    }
  } else if (previous.phase === 'stage-a') {
    if ((await old.yieldVault()) !== previous.v2.stopper.address ||
      (await provider.getBalance(previous.v1.manager.address)).toString() !== previous.reconciliation.parkedEthWei) {
      throw new Error('Stage A parked-state mismatch');
    }
  }
}

async function tx(label, request) {
  const response = await request;
  const receipt = await response.wait();
  if (receipt.status !== 1) throw new Error(`transaction failed: ${label}`);
  m.transactions.push({ label, ...evidence(receipt) });
  return receipt;
}
async function identity(address, receipt, kind = 'mock') {
  const code = await provider.getCode(address);
  if (code === '0x') throw new Error(`no code at ${address}`);
  return { kind, address, runtimeCodeHash: ethers.keccak256(code), evidence: evidence(receipt) };
}
async function deployed(name, args = [], file = name) {
  const a = art(name, file);
  const instance = await new ethers.ContractFactory(a.abi, a.bytecode.object, signer).deploy(...args);
  const receipt = await tx(`deploy.${name}`, instance.deploymentTransaction());
  return { instance, entry: await identity(await instance.getAddress(), receipt) };
}
async function existing(address, label) {
  const block = await provider.getBlock('latest');
  const code = await provider.getCode(address);
  if (code === '0x') throw new Error(`missing ${label}`);
  return { kind: 'real', address, runtimeCodeHash: ethers.keccak256(code), verifiedAt: { blockNumber: block.number, blockHash: block.hash } };
}
const safeAbi = [
  'function setup(address[] owners,uint256 threshold,address to,bytes data,address fallbackHandler,address paymentToken,uint256 payment,address payable paymentReceiver)',
  'function getOwners() view returns (address[])',
  'function getThreshold() view returns (uint256)',
  'function getModulesPaginated(address,uint256) view returns (address[],address)',
  'function getStorageAt(uint256,uint256) view returns (bytes)',
  'function nonce() view returns (uint256)',
  'function approveHash(bytes32)',
  'function getTransactionHash(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,uint256) view returns (bytes32)',
  'function execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes) returns (bool)',
  'event ExecutionSuccess(bytes32 indexed txHash,uint256 payment)',
];
const safeIface = new ethers.Interface(safeAbi);
const safe = () => new ethers.Contract(m.safe.address, safeAbi, signer);
async function safeTx(label, target, data, operation = 0) {
  const s = safe();
  const nonce = await s.nonce();
  const hash = await s.getTransactionHash(target, 0, data, operation, 0, 0, 0, ethers.ZeroAddress, ethers.ZeroAddress, nonce);
  await tx(`safe.approve.${label}`, s.approveHash(hash));
  const signature = ethers.concat([ethers.zeroPadValue(OWNER, 32), ethers.ZeroHash, '0x01']);
  const receipt = await tx(`safe.execute.${label}`, s.execTransaction(target, 0, data, operation, 0, 0, 0, ethers.ZeroAddress, ethers.ZeroAddress, signature));
  const success = receipt.logs.some(log => {
    try { return safeIface.parseLog(log)?.name === 'ExecutionSuccess'; } catch { return false; }
  });
  if (!success) throw new Error(`Safe did not emit ExecutionSuccess: ${label}`);
  return receipt;
}
function call(target, data) {
  return ethers.solidityPacked(['uint8', 'address', 'uint256', 'uint256', 'bytes'], [0, target, 0, ethers.getBytes(data).length, data]);
}
const multiIface = new ethers.Interface(['function multiSend(bytes transactions)']);
async function safeBatch(label, calls) {
  return safeTx(label, MULTISEND, multiIface.encodeFunctionData('multiSend', [ethers.concat(calls)]), 1);
}

if (PHASE === 'v1') {
  await provider.send('anvil_setBalance', [OWNER, ethers.toBeHex(ethers.parseEther('10'))]);
  m.syntheticFunding = { source: 'anvil_setBalance', account: OWNER, amountWei: ethers.parseEther('10').toString() };
  m.dependencies.safeSingleton = await existing(SINGLETON, 'Safe singleton');
  m.dependencies.safeFactory = await existing(FACTORY, 'Safe factory');
  m.dependencies.safeMultiSend = await existing(MULTISEND, 'Safe MultiSend');
  m.dependencies.reth = await existing(RETH, 'Rocket Pool rETH');
  m.dependencies.rocketStorage = await existing(REGISTRY, 'Rocket Pool registry');
  const factoryAbi = [
    'function createProxyWithNonce(address singleton,bytes initializer,uint256 saltNonce) returns (address proxy)',
    'event ProxyCreation(address indexed proxy,address singleton)',
  ];
  const factory = new ethers.Contract(FACTORY, factoryAbi, signer);
  const initializer = safeIface.encodeFunctionData('setup', [[OWNER], 1, ethers.ZeroAddress, '0x', ethers.ZeroAddress, ethers.ZeroAddress, 0, ethers.ZeroAddress]);
  const receipt = await tx('deploy.safe', factory.createProxyWithNonce(SINGLETON, initializer, 0x5EBA));
  const parsed = receipt.logs.map(log => { try { return factory.interface.parseLog(log); } catch { return null; } }).find(x => x?.name === 'ProxyCreation');
  if (!parsed) throw new Error('Safe ProxyCreation event missing');
  const safeAddress = parsed.args.proxy;
  m.safe = { ...await identity(safeAddress, receipt, 'real-safe-proxy'), owners: [OWNER], threshold: 1, version: '1.4.1' };
  if ((await safe().getThreshold()) !== 1n || (await safe().getOwners())[0] !== OWNER) throw new Error('Safe policy mismatch');
  const [modules, next] = await safe().getModulesPaginated('0x0000000000000000000000000000000000000001', 1);
  if (modules.length !== 0 || next !== '0x0000000000000000000000000000000000000001' || BigInt(await safe().getStorageAt(GUARD_SLOT, 1)) !== 0n) throw new Error('Safe module/guard mismatch');

  const weth = await deployed('MockWETH'); m.dependencies.weth = weth.entry;
  const usdc = await deployed('MockUSDC'); m.dependencies.usdc = usdc.entry;
  const bold = await deployed('MockBold'); m.dependencies.bold = bold.entry;
  const sBold = await deployed('HoodiSBoldMock', [bold.entry.address], 'HoodiExternalMocks'); m.v1.sBold = sBold.entry;
  const ethFeed = await deployed('HoodiPriceFeedMock', [2000n * 10n ** 8n], 'HoodiExternalMocks'); m.dependencies.ethUsdFeed = ethFeed.entry;
  const usdFeed = await deployed('HoodiPriceFeedMock', [10n ** 8n], 'HoodiExternalMocks'); m.dependencies.usdcUsdFeed = usdFeed.entry;
  const uni = await deployed('HoodiUniswapMock', [weth.entry.address, usdc.entry.address], 'HoodiExternalMocks'); m.dependencies.uniswap = uni.entry;
  const curve = await deployed('HoodiCurveMock', [usdc.entry.address], 'HoodiExternalMocks'); m.dependencies.curve = curve.entry;
  const beefy = await deployed('HoodiBeefyMock', [curve.entry.address], 'HoodiExternalMocks'); m.dependencies.beefyVault = beefy.entry;
  const harvester = await deployed('HoodiBeefyHarvesterMock', [], 'HoodiExternalMocks'); m.dependencies.beefyHarvester = harvester.entry;
  const ethFlow = await deployed('HoodiEthFlowMock', [OWNER], 'HoodiExternalMocks'); m.dependencies.ethFlow = ethFlow.entry;
  const router = await deployed('EthToBoldRouter', [ethFlow.entry.address, bold.entry.address, OWNER, OWNER]); m.v1.router = router.entry;
  const pyb = await deployed('PYBSeba', [OWNER, sBold.entry.address]); m.v1.pybSeba = pyb.entry;
  const pool = await deployed('SebaPool', [OWNER, OWNER]); m.v1.pool = pool.entry;
  const adapter = await deployed('EUSDUSDCBeefyYieldVault', [OWNER, OWNER, weth.entry.address, usdc.entry.address, uni.entry.address, uni.entry.address, curve.entry.address, beefy.entry.address, ethFeed.entry.address, usdFeed.entry.address]); m.v1.beefyAdapter = adapter.entry;
  const old = await deployed('YieldManager', [OWNER, OWNER, pool.entry.address, router.entry.address, bold.entry.address, sBold.entry.address, pyb.entry.address, adapter.entry.address]); m.v1.manager = old.entry;
  const backpay = await deployed('RocketPoolBackPay', [pool.entry.address]); m.v1.rocketPoolBackPay = backpay.entry;

  await tx('v1.adapter.grantManager', adapter.instance.grantRole(await adapter.instance.YIELDMANAGER_ROLE(), old.entry.address));
  await tx('v1.adapter.revokeBootstrapManager', adapter.instance.revokeRole(await adapter.instance.YIELDMANAGER_ROLE(), OWNER));
  await tx('v1.pyb.bindPool', pyb.instance.setSebaPool(pool.entry.address));
  await tx('v1.pool.bindPyb', pool.instance.setSebaVault(pyb.entry.address));
  await tx('v1.pool.bindManager', pool.instance.setYieldManager(old.entry.address));
  await tx('v1.router.grantManager', router.instance.grantRole(await router.instance.YIELD_MANAGER_ROLE(), old.entry.address));
  await tx('v1.router.revokeBootstrapManager', router.instance.revokeRole(await router.instance.YIELD_MANAGER_ROLE(), OWNER));
  for (const [label, instance] of [['manager', old.instance], ['pool', pool.instance], ['router', router.instance], ['adapter', adapter.instance], ['pyb', pyb.instance]]) {
    const role = await instance.ADMIN_ROLE();
    await tx(`v1.${label}.grantSafeAdmin`, instance.grantRole(role, safeAddress));
    await tx(`v1.${label}.revokeEoaAdmin`, instance.revokeRole(role, OWNER));
    if (await instance.hasRole(role, OWNER) || !(await instance.hasRole(role, safeAddress))) throw new Error(`V1 ${label} admin transfer failed`);
  }
  for (const [label, instance] of [['manager', old.instance], ['pool', pool.instance]]) {
    if (!(await instance.hasRole(await instance.AUTOMATOR_ROLE(), OWNER))) {
      throw new Error(`V1 ${label} test automator role missing`);
    }
  }
  m.reconciliation.v1TestAutomator = OWNER;
  await tx('v1.pool.testReward', signer.sendTransaction({ to: pool.entry.address, value: ethers.parseEther('2') }));
  await tx('v1.pool.sweepRewards', pool.instance.sweepRewards());
  await tx('v1.manager.openEthFlow', old.instance.runBoldConversion(ethers.parseEther('1900')));
  m.reconciliation.v1EthFlowUid = await ethFlow.instance.activeUid(router.entry.address);
  if (m.reconciliation.v1EthFlowUid === ethers.ZeroHash) throw new Error('V1 mock EthFlow order did not open');
  await tx('v1.ethFlow.syntheticFill', ethFlow.instance.settleMockOrder(router.entry.address, ethers.parseEther('1950')));
  await provider.send('evm_increaseTime', [901]);
  await provider.send('evm_mine', []);
  m.syntheticTimeAdvanceSeconds = 901;
  await tx('v1.manager.finalizeEthFlowAndTopup', old.instance.runBoldConversion(0));
  if ((await old.instance.depositId()) !== 0n || (await old.instance.pendingBoldConversion()) !== 0n || (await pool.instance.yieldManager()) !== old.entry.address) throw new Error('V1 baseline not ready');
  m.phase = 'v1-ready';
}

if (PHASE === 'v2') {
  if (m.phase !== 'v1-ready') throw new Error('V1 phase required');
  const yBold = await deployed('HoodiYearnMock', [m.dependencies.bold.address, 'Hoodi mock yBOLD', 'hyBOLD'], 'HoodiExternalMocks'); m.dependencies.yBold = yBold.entry;
  const ysy = await deployed('HoodiYearnMock', [yBold.entry.address, 'Hoodi mock ysyBOLD', 'hysyBOLD'], 'HoodiExternalMocks'); m.dependencies.ysyBold = ysy.entry;
  const managerImpl = await deployed('YieldManagerV2'); m.v2.managerImplementation = managerImpl.entry;
  const managerInit = managerImpl.instance.interface.encodeFunctionData('initialize', [[m.safe.address, ethers.ZeroAddress, m.v1.pool.address, m.dependencies.bold.address, m.v1.sBold.address, m.v1.pybSeba.address, RETH, ysy.entry.address]]);
  const managerProxy = await deployed('ERC1967Proxy', [managerImpl.entry.address, managerInit]); m.v2.manager = managerProxy.entry;
  const rethImpl = await deployed('RethSupporterVault'); m.v2.rethImplementation = rethImpl.entry;
  const rethInit = rethImpl.instance.interface.encodeFunctionData('initialize', [m.safe.address, managerProxy.entry.address, RETH, REGISTRY]);
  const rethProxy = await deployed('ERC1967Proxy', [rethImpl.entry.address, rethInit]); m.v2.rethVault = rethProxy.entry;
  const ysyImpl = await deployed('YsyBoldSupporterVault'); m.v2.ysyBoldImplementation = ysyImpl.entry;
  const ysyInit = ysyImpl.instance.interface.encodeFunctionData('initialize', [m.safe.address, managerProxy.entry.address, ysy.entry.address, yBold.entry.address]);
  const ysyProxy = await deployed('ERC1967Proxy', [ysyImpl.entry.address, ysyInit]); m.v2.ysyBoldVault = ysyProxy.entry;
  const executor = await deployed('SebaV2DirectExecutor', [[managerProxy.entry.address, m.safe.address, RETH, m.dependencies.weth.address, ethers.ZeroAddress, m.dependencies.bold.address, yBold.entry.address, ysy.entry.address, ethers.ZeroAddress, ethers.ZeroAddress, ethers.ZeroAddress, ethers.ZeroAddress, REGISTRY]]); m.v2.executor = executor.entry;
  const settlement = await deployed('HoodiCowSettlementMock', [m.dependencies.bold.address, OWNER], 'HoodiExternalMocks'); m.dependencies.cowSettlement = settlement.entry;
  const relayerAddress = await settlement.instance.vaultRelayer();
  m.dependencies.cowRelayer = { kind: 'mock', creationKind: 'internal-create', address: relayerAddress, runtimeCodeHash: ethers.keccak256(await provider.getCode(relayerAddress)), evidence: settlement.entry.evidence };
  const cow = await deployed('SebaCowIntentModule', [managerProxy.entry.address, m.safe.address, m.dependencies.weth.address, RETH, m.dependencies.bold.address, settlement.entry.address]); m.v2.cowModule = cow.entry;
  const manager = contract('YieldManagerV2', managerProxy.entry.address);
  await safeTx('v2.bindVaults', managerProxy.entry.address, manager.interface.encodeFunctionData('bindVaults', [rethProxy.entry.address, ysyProxy.entry.address]));
  await safeTx('v2.configureDisabledExecutor', managerProxy.entry.address, manager.interface.encodeFunctionData('configureExecution', [executor.entry.address, ethers.parseEther('10'), ethers.parseEther('10'), ethers.parseEther('10')]));
  await safeTx('v2.configureDisabledCow', managerProxy.entry.address, manager.interface.encodeFunctionData('configureCowModule', [cow.entry.address]));
  if (await manager.intakeEnabled() || await manager.executionEnabled() || await cow.instance.enabled() || await executor.instance.enabled()) throw new Error('V2 candidate unexpectedly enabled');
  m.phase = 'v2-staged';
}

if (PHASE === 'stage-a') {
  if (m.phase !== 'v2-staged') throw new Error('V2 staging required');
  const stopper = await deployed('LegacyIntakeStopper'); m.v2.stopper = stopper.entry;
  const old = contract('YieldManager', m.v1.manager.address);
  const data = old.interface.encodeFunctionData('setYieldVault', [stopper.entry.address]);
  const receipt = await safeBatch('stageA', [call(m.v1.manager.address, data)]);
  m.cutover.stageA = evidence(receipt);
  const parkedEth = await provider.getBalance(m.v1.manager.address);
  if (parkedEth <= 0n || (await old.principalValue()) !== 0n || (await old.yieldVault()) !== stopper.entry.address) throw new Error('Stage A exit/stopper mismatch');
  m.reconciliation.parkedEthWei = parkedEth.toString();
  m.phase = 'stage-a';
}

if (PHASE === 'stage-b') {
  if (m.phase !== 'stage-a') throw new Error('Stage A required');
  const old = contract('YieldManager', m.v1.manager.address);
  const adapter = contract('EUSDUSDCBeefyYieldVault', m.v1.beefyAdapter.address);
  const router = contract('EthToBoldRouter', m.v1.router.address);
  const manager = contract('YieldManagerV2', m.v2.manager.address);
  const pool = contract('SebaPool', m.v1.pool.address);
  const beefy = contract('HoodiBeefyMock', m.dependencies.beefyVault.address, 'HoodiExternalMocks');
  const owners = await safe().getOwners();
  const [modules, next] = await safe().getModulesPaginated('0x0000000000000000000000000000000000000001', 1);
  if (modules.length || next !== '0x0000000000000000000000000000000000000001' || BigInt(await safe().getStorageAt(GUARD_SLOT, 1)) !== 0n) throw new Error('Safe policy changed');
  const latest = await provider.getBlock('latest');
  const expectedEth = await provider.getBalance(m.v1.manager.address);
  if (expectedEth.toString() !== m.reconciliation.parkedEthWei || (await old.depositId()) !== 0n || (await old.pendingBoldConversion()) !== 0n) throw new Error('legacy snapshot changed');
  const configuration = {
    oldManager: m.v1.manager.address, destination: m.v2.manager.address, treasury: m.safe.address,
    pool: m.v1.pool.address, oldVault: m.v1.beefyAdapter.address, stagingVault: m.v2.stopper.address,
    oldRouter: m.v1.router.address, expectedEth, expiry: BigInt(latest.timestamp + 900),
    oldPrincipal: await old.principalValue(), oldDepositId: await old.depositId(),
    adapterPrincipal: await adapter.principalValue(), adapterShares: await adapter.principalShares(),
    actualBeefyShares: await beefy.balanceOf(m.v1.beefyAdapter.address), oldIdleEth: expectedEth,
    safeOwnersHash: ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(['address[]'], [owners])),
    safeThreshold: await safe().getThreshold(), rethBps: await manager.rethBps(),
    manifest: m.previousManifestHash, maximumRouterEth: 0, maximumOldBold: 0,
    maximumOldSBold: 0, maximumRouterBold: 0,
  };
  const handoff = await deployed('LegacyProtocolPrincipalHandoff', [configuration]); m.v2.handoff = handoff.entry;
  const arm = manager.interface.encodeFunctionData('armLegacyImport', [handoff.entry.address, expectedEth, configuration.expiry, configuration.manifest]);
  const calls = [
    call(m.v2.manager.address, arm),
    call(handoff.entry.address, handoff.instance.interface.encodeFunctionData('assertPreMigration')),
    call(m.v1.manager.address, old.interface.encodeFunctionData('setYieldVault', [handoff.entry.address])),
    call(m.v1.manager.address, old.interface.encodeFunctionData('depositPrincipalIntoYieldVault')),
    call(m.v2.manager.address, manager.interface.encodeFunctionData('setIntakeEnabled', [true])),
    call(m.v1.pool.address, pool.interface.encodeFunctionData('setYieldManager', [m.v2.manager.address])),
    call(handoff.entry.address, handoff.instance.interface.encodeFunctionData('assertPostMigration')),
  ];
  const receipt = await safeBatch('stageB', calls); m.cutover.stageB = evidence(receipt);
  if ((await pool.yieldManager()) !== m.v2.manager.address || !(await manager.legacyImported()) || !(await handoff.instance.used()) || (await provider.getBalance(m.v1.manager.address)) !== 0n || (await manager.pendingEth(1)) + (await manager.pendingEth(2)) !== expectedEth) throw new Error('Stage B reconciliation failed');
  m.reconciliation.importedEthWei = expectedEth.toString();
  m.phase = 'cutover';
}

const checkpointBlock = await provider.getBlock('latest');
m.checkpoint = { blockNumber: checkpointBlock.number, blockHash: checkpointBlock.hash };
const json = `${JSON.stringify(clean(m), null, 2)}\n`;
const hash = ethers.keccak256(ethers.toUtf8Bytes(json));
const outDir = path.resolve('broadcast/hoodi-local');
fs.mkdirSync(outDir, { recursive: true });
const outPath = path.join(outDir, `manifest-${m.phase}-${hash.slice(2, 18)}.json`);
fs.writeFileSync(outPath, json, { flag: 'wx' });
console.log(JSON.stringify({ phase: m.phase, manifest: outPath, hash, checkpoint: m.checkpoint }));
