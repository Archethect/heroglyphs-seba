// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IYieldManagerV2 } from "../interfaces/v2/IYieldManagerV2.sol";
import { IV2Executor } from "../interfaces/v2/IV2Executor.sol";
import { IV2SupporterVault } from "../interfaces/v2/IV2SupporterVault.sol";
import { ISBOLD } from "../vendor/liquity/ISBOLD.sol";
import { IPYBSeba } from "../interfaces/IPYBSeba.sol";

/// @title Fixed ERC4626 integration identity and deposit quote
/// @author Seba
/// @notice Narrow views used for identity checks and independent conversion bounds.
interface IV2AssetIdentity {
    /// @notice Return the vault's underlying token.
    /// @return assetToken Fixed ERC20 asset address.
    function asset() external view returns (address);
    /// @notice Quote shares before an exact asset deposit, without changing state.
    /// @param assets Underlying token base units to deposit.
    /// @return shares Minimum canonical share quote, in share base units.
    function previewDeposit(uint256 assets) external view returns (uint256);
}

/// @title Immutable one-shot handoff identity
/// @author Seba
/// @notice Identities validated before the exact legacy import is armed.
interface IV2HandoffIdentity {
    /// @notice Return the fixed new manager proxy.
    /// @return target Authorized import receiver.
    function destination() external view returns (address);
    /// @notice Return the exact approved import quantity.
    /// @return amount Native ETH wei, not old strategy basis units.
    function expectedEth() external view returns (uint256);
    /// @notice Return the last valid import timestamp, inclusive.
    /// @return timestamp Unix seconds.
    function expiry() external view returns (uint256);
    /// @notice Return the fixed deployment chain.
    /// @return chain EVM chain ID.
    function chainId() external view returns (uint256);
}

/// @title Seba V2 protocol capital and yield coordinator
/// @author Seba
/// @notice Native supporter positions remain in independently withdrawable vaults.
/// @dev The fixed treasury Safe can upgrade all logic. Operators cannot configure or recover assets.
contract YieldManagerV2 is IYieldManagerV2, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice Fixed Safe administration, upgrade and recovery authority.
    address public treasury;
    /// @notice The only caller authorized to submit fresh protocol reward ETH.
    address public sebaPool;
    /// @notice Fixed reward token identities.
    address public bold;
    /// @notice Fixed sBOLD reward shares; their ERC4626 asset must be BOLD.
    address public sBold;
    /// @notice Existing pybSeba reward recipient; its asset must be sBOLD.
    address public pybSeba;
    /// @notice Fixed investment token identities and the ysyBOLD basis token.
    address public reth;
    /// @notice Fixed Yearn staked yBOLD share token used for the second native leg.
    address public ysyBold;
    /// @notice Canonical native principal basis token underlying ysyBOLD.
    address public yBold;
    /// @notice Swap intermediary identities fixed by the first approved executor configuration.
    address public weth;
    /// @notice USDC swap intermediary, pinned by the first executor configuration.
    address public usdc;
    /// @notice Once-bound native vault proxies: 0=rETH, 1=ysyBOLD.
    address[2] public vaults;
    /// @notice Assigned ETH: 0=immediate rewards, 1=rETH protocol, 2=ysyBOLD protocol.
    uint256[3] public pendingEth;
    /// @notice Collected native tokens classified by leg and capital bucket.
    mapping(uint8 leg => mapping(uint8 bucket => uint256 tokens)) public harvestInventory;
    /// @notice Classified reward inventory, not principal.
    uint256 public pendingBold;
    /// @notice Classified sBOLD reward shares awaiting one completed pybSeba top-up.
    uint256 public pendingSBold;
    /// @notice Future invested-half weights, never applied retroactively.
    uint16 public rethBps;
    /// @notice ysyBOLD portion of the future invested half, basis points summing to 10,000 with rETH.
    uint16 public ysyBoldBps;
    /// @notice Monotonic future-allocation version, also fixed for an armed legacy import.
    uint64 public weightVersion;
    /// @notice Intake and automated execution are independently disabled initially.
    bool public intakeEnabled;
    /// @notice Whether bounded operational conversions/deployment may execute.
    bool public executionEnabled;
    /// @notice Irreversible buffer-retirement flag; only a reviewed upgrade can restore operations.
    bool public buffersRecovered;
    /// @notice Bounded maintenance operators with no configuration, upgrade or recovery authority.
    mapping(address operator => bool authorized) public operators;
    /// @notice Typed fixed-route executor and per-operation amount caps.
    IV2Executor public executor;
    /// @notice Maximum ETH wei spent in one operator execution.
    uint256 public maximumEth;
    /// @notice Maximum native harvest tokens converted per operation, indexed by leg.
    uint256[2] public maximumYieldTokens;
    /// @notice Exact, expiring and permanently one-shot legacy import configuration.
    address public legacyHandoff;
    /// @notice Exact approved one-shot import in ETH wei.
    uint256 public legacyExpectedEth;
    /// @notice Inclusive legacy import expiration timestamp.
    uint256 public legacyExpiry;
    /// @notice Future-allocation version committed when the import is armed.
    uint64 public legacyWeightVersion;
    /// @notice True only after the exact successful import; replay is impossible.
    bool public legacyImported;
    /// @notice Immutable approved legacy-import evidence commitment after arming.
    bytes32 public legacyManifest;
    uint256[40] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlySafe() {
        if (msg.sender != treasury) revert Unauthorized();
        _;
    }
    modifier onlyOperator() {
        if (msg.sender != treasury) {
            if (!operators[msg.sender]) revert Unauthorized();
        }
        _;
    }

    /// @notice Unsolicited ETH remains unassigned until explicitly classified by the Safe.
    receive() external payable {}

    /// @inheritdoc IYieldManagerV2
    function initialize(Initialization calldata c) external initializer {
        _contract(c.treasury);
        _contract(c.pool);
        _contract(c.bold);
        _contract(c.sBold);
        _contract(c.pybSeba);
        _contract(c.reth);
        _contract(c.ysyBold);
        if (
            c.treasury == address(this) ||
            c.pool == address(this) ||
            c.bold == c.sBold ||
            c.reth == c.ysyBold ||
            IV2AssetIdentity(c.sBold).asset() != c.bold ||
            IV2AssetIdentity(c.pybSeba).asset() != c.sBold
        ) {
            revert InvalidConfiguration();
        }
        address basis = IV2AssetIdentity(c.ysyBold).asset();
        _contract(basis);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        treasury = c.treasury;
        sebaPool = c.pool;
        bold = c.bold;
        sBold = c.sBold;
        pybSeba = c.pybSeba;
        reth = c.reth;
        ysyBold = c.ysyBold;
        yBold = basis;
        rethBps = 5_000;
        ysyBoldBps = 5_000;
        weightVersion = 1;
        if (c.operator != address(0)) {
            operators[c.operator] = true;
            emit OperatorSet(c.operator, true);
        }
        emit ManagerInitialized(c.pool, c.treasury, c.bold, c.sBold, c.pybSeba, c.reth, c.ysyBold);
    }

    /// @inheritdoc IYieldManagerV2
    function bindVaults(address r, address y) external onlySafe {
        if (intakeEnabled || vaults[0] != address(0) || r == y) revert InvalidConfiguration();
        _validateVault(r, reth, address(0));
        _validateVault(y, ysyBold, yBold);
        vaults[0] = r;
        vaults[1] = y;
        emit VaultsBound(r, y);
    }

    /// @inheritdoc IYieldManagerV2
    function depositFunds() external payable nonReentrant {
        if (msg.sender != sebaPool) revert Unauthorized();
        if (!intakeEnabled || buffersRecovered) revert IntakeDisabled();
        if (msg.value == 0) revert InvalidAmount();
        uint256 reward = msg.value / 2;
        (uint256 r, uint256 y) = _assignInvestment(msg.value - reward);
        pendingEth[0] += reward;
        emit PoolFundsAssigned(msg.value, reward, r, y, weightVersion);
    }

    /// @inheritdoc IYieldManagerV2
    function setFutureInvestmentWeights(uint16 r, uint16 y) external onlySafe {
        if (uint256(r) + y != 10_000) revert InvalidConfiguration();
        if (legacyHandoff != address(0) && !legacyImported) revert InvalidImport();
        rethBps = r;
        ysyBoldBps = y;
        ++weightVersion;
        emit FutureWeightsSet(r, y, weightVersion);
    }

    /// @inheritdoc IYieldManagerV2
    function setIntakeEnabled(bool enabled) external onlySafe {
        if (enabled && (buffersRecovered || vaults[0] == address(0))) revert InvalidConfiguration();
        intakeEnabled = enabled;
        emit IntakeSet(enabled);
    }

    /// @inheritdoc IYieldManagerV2
    function configureExecution(address target, uint256 ethCap, uint256 rCap, uint256 yCap) external onlySafe {
        if (executionEnabled || buffersRecovered || ethCap == 0 || rCap == 0 || yCap == 0)
            revert InvalidConfiguration();
        _contract(target);
        IV2Executor.Config memory c = IV2Executor(target).configuration();
        if (
            c.manager != address(this) ||
            c.treasury != treasury ||
            c.reth != reth ||
            c.ysyBold != ysyBold ||
            c.bold != bold ||
            c.yBold != yBold ||
            c.weth.code.length == 0 ||
            c.usdc.code.length == 0 ||
            (weth != address(0) && (c.weth != weth || c.usdc != usdc))
        ) revert InvalidConfiguration();
        if (address(executor) != address(0)) {
            if (
                IERC20(reth).allowance(address(this), address(executor)) != 0 ||
                IERC20(ysyBold).allowance(address(this), address(executor)) != 0
            ) revert InvalidConfiguration();
        }
        executor = IV2Executor(target);
        weth = c.weth;
        usdc = c.usdc;
        maximumEth = ethCap;
        maximumYieldTokens[0] = rCap;
        maximumYieldTokens[1] = yCap;
        emit ExecutionConfigured(target, ethCap, rCap, yCap);
    }

    /// @inheritdoc IYieldManagerV2
    function setExecutionEnabled(bool enabled) external onlySafe {
        if (
            enabled &&
            (buffersRecovered || vaults[0] == address(0) || address(executor) == address(0) || !executor.enabled())
        ) revert InvalidConfiguration();
        executionEnabled = enabled;
        emit ExecutionSet(enabled);
    }

    /// @inheritdoc IYieldManagerV2
    function setOperator(address operator, bool enabled) external onlySafe {
        if (operator == address(0) || operator == treasury) revert InvalidConfiguration();
        operators[operator] = enabled;
        emit OperatorSet(operator, enabled);
    }

    /// @inheritdoc IYieldManagerV2
    function deployProtocolPrincipal(
        uint8 leg,
        uint256 amount,
        uint256 minTokens,
        uint256 minBasis,
        uint256 deadline
    ) external nonReentrant onlyOperator {
        _leg(leg);
        _execution(deadline);
        _ethAmount(amount, pendingEth[leg + 1]);
        _ethCustody();
        _yieldCustody(leg);
        pendingEth[leg + 1] -= amount;
        IERC20 token = IERC20(leg == 0 ? reth : ysyBold);
        uint256 beforeTokens = token.balanceOf(address(this));
        uint256 beforeEth = address(this).balance;
        uint256 output = leg == 0
            ? executor.investReth{ value: amount }(minTokens, deadline)
            : executor.investYsyBold{ value: amount }(minTokens, deadline);
        uint256 received = token.balanceOf(address(this)) - beforeTokens;
        if (address(this).balance != beforeEth - amount) revert InvalidTokenDelta();
        if (received == 0 || received != output) revert InvalidTokenDelta();
        if (received < minTokens) revert InsufficientOutput();
        token.forceApprove(vaults[leg], received);
        uint256 basis = IV2SupporterVault(vaults[leg]).depositProtocol(received, minBasis, deadline);
        token.forceApprove(vaults[leg], 0);
        if (token.balanceOf(address(this)) != beforeTokens || basis == 0) revert InvalidTokenDelta();
        _ethCustody();
        _yieldCustody(leg);
        emit ProtocolDeployed(leg, amount, received, basis);
    }

    /// @inheritdoc IYieldManagerV2
    function convertEthRewards(uint256 amount, uint256 minBold, uint256 deadline) external nonReentrant onlyOperator {
        _execution(deadline);
        _ethAmount(amount, pendingEth[0]);
        _ethCustody();
        _boldCustody();
        pendingEth[0] -= amount;
        uint256 beforeTokens = IERC20(bold).balanceOf(address(this));
        uint256 beforeEth = address(this).balance;
        uint256 output = executor.convertEthToBold{ value: amount }(minBold, deadline);
        if (address(this).balance != beforeEth - amount) revert InvalidTokenDelta();
        _creditBold(beforeTokens, output, minBold);
        _ethCustody();
        _boldCustody();
        emit RewardsConverted(0, 0, amount, output);
    }

    /// @inheritdoc IYieldManagerV2
    function convertHarvest(
        uint8 leg,
        uint8 which,
        uint256 amount,
        uint256 minBold,
        uint256 deadline
    ) external nonReentrant onlyOperator {
        _leg(leg);
        _bucket(which);
        _execution(deadline);
        _yieldCustody(leg);
        _boldCustody();
        if (amount == 0 || amount > maximumYieldTokens[leg] || amount > harvestInventory[leg][which])
            revert InvalidAmount();
        harvestInventory[leg][which] -= amount;
        IERC20 token = IERC20(leg == 0 ? reth : ysyBold);
        uint256 beforeInput = token.balanceOf(address(this));
        uint256 beforeBold = IERC20(bold).balanceOf(address(this));
        token.forceApprove(address(executor), amount);
        uint256 output = leg == 0
            ? executor.convertRethToBold(amount, minBold, deadline)
            : executor.convertYsyToBold(amount, minBold, deadline);
        token.forceApprove(address(executor), 0);
        if (token.balanceOf(address(this)) != beforeInput - amount) revert InvalidTokenDelta();
        _creditBold(beforeBold, output, minBold);
        _yieldCustody(leg);
        _boldCustody();
        emit RewardsConverted(leg + 1, which, amount, output);
    }

    /// @inheritdoc IYieldManagerV2
    function convertBoldToSBold(
        uint256 amount,
        uint256 minShares,
        uint256 deadline
    ) external nonReentrant onlyOperator {
        _execution(deadline);
        _boldCustody();
        _sBoldCustody();
        if (amount == 0 || amount > pendingBold || minShares == 0) revert InvalidAmount();
        uint256 canonicalFloor = IV2AssetIdentity(sBold).previewDeposit(amount);
        if (canonicalFloor == 0) revert InsufficientOutput();
        pendingBold -= amount;
        uint256 beforeBold = IERC20(bold).balanceOf(address(this));
        uint256 beforeShares = IERC20(sBold).balanceOf(address(this));
        IERC20(bold).forceApprove(sBold, amount);
        uint256 output = ISBOLD(sBold).deposit(amount, address(this));
        IERC20(bold).forceApprove(sBold, 0);
        uint256 received = IERC20(sBold).balanceOf(address(this)) - beforeShares;
        if (received == 0 || received != output || IERC20(bold).balanceOf(address(this)) != beforeBold - amount)
            revert InvalidTokenDelta();
        if (received < minShares || received < canonicalFloor) revert InsufficientOutput();
        pendingSBold += received;
        emit SBoldMinted(amount, received);
    }

    /// @inheritdoc IYieldManagerV2
    function donateSBold(uint256 amount) external nonReentrant onlyOperator {
        _execution(block.timestamp);
        _sBoldCustody();
        if (amount == 0 || amount > pendingSBold) revert InvalidAmount();
        pendingSBold -= amount;
        uint256 beforeTokens = IERC20(sBold).balanceOf(address(this));
        uint256 beforeRecipient = IERC20(sBold).balanceOf(pybSeba);
        IERC20(sBold).forceApprove(pybSeba, amount);
        IPYBSeba(pybSeba).topup(amount);
        IERC20(sBold).forceApprove(pybSeba, 0);
        if (
            IERC20(sBold).balanceOf(address(this)) != beforeTokens - amount ||
            IERC20(sBold).balanceOf(pybSeba) != beforeRecipient + amount
        ) revert InvalidTokenDelta();
        emit DonationCompleted(amount);
    }

    /// @inheritdoc IYieldManagerV2
    function onYieldReceived(uint8 which, uint256 amount) external nonReentrant {
        _bucket(which);
        uint8 leg;
        if (msg.sender == vaults[0] && msg.sender != address(0)) leg = 0;
        else if (msg.sender == vaults[1] && msg.sender != address(0)) leg = 1;
        else revert Unauthorized();
        if (amount == 0) revert InvalidAmount();
        harvestInventory[leg][which] += amount;
        _yieldCustody(leg);
        // Remains available during pauses/manager recovery so terminal leaf reconciliation cannot be blocked.
        emit HarvestReceived(leg, which, amount);
    }

    /// @inheritdoc IYieldManagerV2
    function armLegacyImport(address handoff, uint256 expectedEth, uint256 expiry, bytes32 manifest) external onlySafe {
        if (
            intakeEnabled ||
            executionEnabled ||
            buffersRecovered ||
            legacyHandoff != address(0) ||
            expectedEth == 0 ||
            expiry < block.timestamp ||
            manifest == bytes32(0)
        ) revert InvalidImport();
        _contract(handoff);
        IV2HandoffIdentity h = IV2HandoffIdentity(handoff);
        if (
            h.destination() != address(this) ||
            h.expectedEth() != expectedEth ||
            h.expiry() != expiry ||
            h.chainId() != block.chainid
        ) revert InvalidImport();
        legacyHandoff = handoff;
        legacyExpectedEth = expectedEth;
        legacyExpiry = expiry;
        legacyWeightVersion = weightVersion;
        legacyManifest = manifest;
        emit LegacyImportArmed(handoff, expectedEth, expiry, weightVersion, manifest);
    }

    /// @inheritdoc IYieldManagerV2
    function importLegacyPrincipal() external payable nonReentrant {
        if (
            msg.sender != legacyHandoff ||
            legacyImported ||
            buffersRecovered ||
            msg.value != legacyExpectedEth ||
            block.timestamp > legacyExpiry ||
            legacyWeightVersion != weightVersion
        ) revert InvalidImport();
        legacyImported = true;
        (uint256 r, uint256 y) = _assignInvestment(msg.value);
        emit LegacyPrincipalImported(msg.value, r, y);
    }

    /// @inheritdoc IYieldManagerV2
    function recognizeEthSurplus(uint8 purpose, uint256 amount) external onlySafe {
        if (buffersRecovered || purpose > 2 || amount == 0 || amount > address(this).balance - _assignedEth())
            revert InvalidAmount();
        pendingEth[purpose] += amount;
        emit EthSurplusRecognized(purpose, amount);
    }

    /// @inheritdoc IYieldManagerV2
    function recoverBuffers(bytes32 manifest) external nonReentrant onlySafe {
        if (manifest == bytes32(0)) revert InvalidConfiguration();
        _custody();
        uint256 ethAmount = _assignedEth();
        uint256 b = pendingBold;
        uint256 s = pendingSBold;
        uint256 r = harvestInventory[0][0] + harvestInventory[0][1];
        uint256 y = harvestInventory[1][0] + harvestInventory[1][1];
        if (buffersRecovered && ethAmount + b + s + r + y == 0) revert BuffersAlreadyRecovered();
        bytes32 accountingHash = keccak256(
            abi.encode(
                pendingEth,
                harvestInventory[0][0],
                harvestInventory[0][1],
                harvestInventory[1][0],
                harvestInventory[1][1],
                b,
                s
            )
        );
        intakeEnabled = false;
        executionEnabled = false;
        buffersRecovered = true;
        delete pendingEth;
        pendingBold = 0;
        pendingSBold = 0;
        delete harvestInventory[0][0];
        delete harvestInventory[0][1];
        delete harvestInventory[1][0];
        delete harvestInventory[1][1];
        _sendToken(bold, b);
        _sendToken(sBold, s);
        _sendToken(reth, r);
        _sendToken(ysyBold, y);
        if (ethAmount != 0) {
            (bool ok, ) = treasury.call{ value: ethAmount }("");
            if (!ok) revert TransferFailed();
        }
        emit BuffersRecovered(manifest, ethAmount, b, s, r, y, accountingHash);
    }

    /// @inheritdoc IYieldManagerV2
    function rescueToken(address token, uint256 amount) external nonReentrant onlySafe {
        if (
            token == bold ||
            token == sBold ||
            token == reth ||
            token == ysyBold ||
            token == yBold ||
            token == weth ||
            token == usdc
        ) revert CoreAsset();
        if (amount == 0) revert InvalidAmount();
        _sendToken(token, amount);
        emit NoncoreRescued(token, amount);
    }

    function _assignInvestment(uint256 amount) internal returns (uint256 r, uint256 y) {
        r = Math.mulDiv(amount, rethBps, 10_000);
        y = amount - r;
        pendingEth[1] += r;
        pendingEth[2] += y;
    }
    function _assignedEth() internal view returns (uint256) {
        return pendingEth[0] + pendingEth[1] + pendingEth[2];
    }
    function _execution(uint256 deadline) internal view {
        if (!executionEnabled || buffersRecovered) revert ExecutionDisabled();
        if (block.timestamp > deadline) revert Expired();
    }
    function _ethAmount(uint256 amount, uint256 available) internal view {
        if (amount == 0 || amount > maximumEth || amount > available) revert InvalidAmount();
    }
    function _creditBold(uint256 beforeTokens, uint256 output, uint256 minimum) internal {
        uint256 delta = IERC20(bold).balanceOf(address(this)) - beforeTokens;
        if (delta == 0 || delta != output) revert InvalidTokenDelta();
        if (delta < minimum) revert InsufficientOutput();
        pendingBold += delta;
    }
    function _validateVault(address target, address token, address basis) internal view {
        _contract(target);
        IV2SupporterVault v = IV2SupporterVault(target);
        if (v.asset() != token || v.basisAsset() != basis || v.manager() != address(this) || v.treasury() != treasury)
            revert InvalidConfiguration();
    }
    function _custody() internal view {
        _ethCustody();
        _boldCustody();
        _sBoldCustody();
        _yieldCustody(0);
        _yieldCustody(1);
    }
    function _ethCustody() internal view {
        if (address(this).balance < _assignedEth()) revert InvalidTokenDelta();
    }
    function _boldCustody() internal view {
        if (IERC20(bold).balanceOf(address(this)) < pendingBold) revert InvalidTokenDelta();
    }
    function _sBoldCustody() internal view {
        if (IERC20(sBold).balanceOf(address(this)) < pendingSBold) revert InvalidTokenDelta();
    }
    function _yieldCustody(uint8 leg) internal view {
        if (
            IERC20(leg == 0 ? reth : ysyBold).balanceOf(address(this)) <
            harvestInventory[leg][0] + harvestInventory[leg][1]
        ) revert InvalidTokenDelta();
    }
    function _sendToken(address token, uint256 amount) internal {
        if (amount == 0) return;
        uint256 beforeSender = IERC20(token).balanceOf(address(this));
        uint256 beforeReceiver = IERC20(token).balanceOf(treasury);
        IERC20(token).safeTransfer(treasury, amount);
        if (
            IERC20(token).balanceOf(address(this)) != beforeSender - amount ||
            IERC20(token).balanceOf(treasury) != beforeReceiver + amount
        ) revert InvalidTokenDelta();
    }
    function _contract(address target) internal view {
        if (target.code.length == 0) revert InvalidConfiguration();
    }
    function _leg(uint8 leg) internal pure {
        if (leg > 1) revert InvalidLeg();
    }
    function _bucket(uint8 which) internal pure {
        if (which > 1) revert InvalidBucket();
    }
    /// @dev Upgrade authority is fixed to the Safe, independent of all bounded operators.
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal view override onlySafe {
        // The fixed Safe modifier is the complete authorization check.
    }
}
