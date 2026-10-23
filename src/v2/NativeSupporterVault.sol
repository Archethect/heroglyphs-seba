// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IV2SupporterVault, IV2VaultYieldReceiver } from "../interfaces/v2/IV2SupporterVault.sol";

// Explicit lifecycle commitments and independent ledgers intentionally exceed the state-count heuristic.
// solhint-disable max-states-count
/// @title Segregated native-token supporter and protocol custody
/// @author Seba contributors
/// @notice Principal is native-value basis, not a promise to return the deposited token count.
/// @dev Not ERC4626. Safe upgrade authority ultimately controls all custody. Future upgrades must preserve this layout.
abstract contract NativeSupporterVault is IV2SupporterVault, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    // solhint-enable max-states-count
    using SafeERC20 for IERC20;

    /// @notice Original supporter lock, retained during recovery.
    uint256 public constant LOCK_PERIOD = 30 days;
    /// @notice Segregated supporter bucket index.
    uint8 public constant SUPPORTER = 0;
    /// @notice Segregated protocol bucket index.
    uint8 public constant PROTOCOL = 1;
    /// @inheritdoc IV2SupporterVault
    address public override asset;
    /// @inheritdoc IV2SupporterVault
    address public override basisAsset;
    /// @inheritdoc IV2SupporterVault
    address public override manager;
    /// @inheritdoc IV2SupporterVault
    address public override treasury;
    /// @notice Next monotonically increasing local position ID, starting at one.
    uint256 public nextPositionId;
    /// @notice Safe-approved native-basis minimum per entry, initially unset.
    uint256 public minimumBasis;
    /// @notice Safe-approved native-token harvest cap, initially unset.
    uint256 public maximumHarvest;
    /// @notice Whether new capital may enter, independent of native exits.
    bool public entriesEnabled;
    /// @notice Whether authorized recognized-yield collection is enabled.
    bool public harvestEnabled;
    /// @notice Collection-only operators with no upgrade, recovery or principal authority.
    mapping(address operator => bool enabled) public operators;
    /// @notice Terminal recovery lifecycle, independent of ordinary pause flags.
    RecoveryState public recoveryState;
    /// @notice Immutable chain/proxy/snapshot identity after export.
    bytes32 public recoveryInstance;
    /// @notice Immutable initial custody-evidence commitment.
    bytes32 public initialManifest;
    /// @notice Immutable final classification/budget commitment, set once at activation.
    bytes32 public settlementManifest;
    /// @notice Exclusive upper position-ID boundary captured at export.
    uint256 public recoveryPositionBoundary;
    /// @notice Unassigned native tokens quarantined at the recovery snapshot.
    uint256 public recoverySurplus;
    /// @notice Whether unavailable canonical valuation required an explicit Safe budget attestation.
    bool public exceptionalSettlement;
    mapping(uint256 id => Position record) private _positions;
    Bucket[2] private _buckets;
    RecoveryBucket[2] private _recovery;
    uint256[40] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlySafe() {
        if (msg.sender != treasury) revert Unauthorized();
        _;
    }
    modifier onlyNormal() {
        if (recoveryState != RecoveryState.Normal) revert WrongState();
        _;
    }

    /// @dev Initializes identities once. The Safe and manager must already be deployed contracts.
    function __NativeSupporterVault_init(
        address safe,
        address coordinator,
        address token,
        address basis
    ) internal onlyInitializing {
        if (
            safe.code.length == 0 ||
            coordinator.code.length == 0 ||
            token.code.length == 0 ||
            safe == address(this) ||
            coordinator == address(this) ||
            safe == token ||
            coordinator == token ||
            IERC20Metadata(token).decimals() != 18
        ) {
            revert InvalidConfiguration();
        }
        if (basis != address(0) && (basis.code.length == 0 || IERC20Metadata(basis).decimals() != 18))
            revert InvalidConfiguration();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        treasury = safe;
        manager = coordinator;
        asset = token;
        basisAsset = basis;
        nextPositionId = 1;
    }

    /// @inheritdoc IV2SupporterVault
    function position(uint256 id) external view returns (Position memory) {
        return _positions[id];
    }
    /// @inheritdoc IV2SupporterVault
    function bucket(uint8 which) external view returns (Bucket memory) {
        _checkBucket(which);
        return _buckets[which];
    }
    /// @inheritdoc IV2SupporterVault
    function recoveryBucket(uint8 which) external view returns (RecoveryBucket memory) {
        _checkBucket(which);
        return _recovery[which];
    }
    /// @inheritdoc IV2SupporterVault
    function rateSnapshot() public view returns (uint256 numerator, uint256 denominator) {
        (numerator, denominator) = _readRate();
        if (denominator == 0) revert InvalidRate();
    }
    /// @notice Canonical native basis of tokens. Failed views are distinct from a successful zero valuation.
    /// @param tokens Fixed native-token amount to value under the canonical rate.
    /// @return Recognized ETH-wei or yBOLD-unit value, floored.
    function canonicalValue(uint256 tokens) external view returns (uint256) {
        (uint256 n, uint256 d) = rateSnapshot();
        return Math.mulDiv(tokens, n, d);
    }
    /// @inheritdoc IV2SupporterVault
    function accounting(
        uint8 which
    ) external view returns (uint256 value, uint256 deficit, uint256 reserve, uint256 carry) {
        _checkBucket(which);
        (uint256 n, uint256 d) = rateSnapshot();
        Bucket storage b = _buckets[which];
        value = Math.mulDiv(b.tokens, n, d);
        deficit = b.basis > value ? b.basis - value : 0;
        reserve = _reserve(b.basis, b.tokens, n, d);
        carry = b.tokens - reserve;
    }
    /// @inheritdoc IV2SupporterVault
    function previewWithdraw(uint256 id) external view returns (uint256) {
        Position storage p = _positions[id];
        _open(p);
        if (recoveryState == RecoveryState.Settlement) return _settlementTokens(SUPPORTER, p.basis);
        if (recoveryState != RecoveryState.Normal) revert WrongState();
        (uint256 n, uint256 d) = rateSnapshot();
        return _principalTokens(_buckets[SUPPORTER], p.basis, n, d);
    }

    /// @notice Safe-only entry configuration; zero minimum cannot enable new capital.
    /// @param minBasis Minimum native-value principal per entry; production value requires explicit approval.
    /// @param enabled Whether public and protocol entry may proceed, subject to accounting/freshness checks.
    function configureEntry(uint256 minBasis, bool enabled) external onlySafe onlyNormal {
        if (enabled && minBasis == 0) revert InvalidConfiguration();
        minimumBasis = minBasis;
        entriesEnabled = enabled;
        emit EntryConfigured(minBasis, enabled);
    }
    /// @notice Safe-only harvest cap and pause, separate from native principal exits.
    /// @param maxTokens Maximum native-token quantity per authorized collection.
    /// @param enabled Whether bounded carry collection is enabled.
    function configureHarvest(uint256 maxTokens, bool enabled) external onlySafe onlyNormal {
        if (enabled && maxTokens == 0) revert InvalidConfiguration();
        maximumHarvest = maxTokens;
        harvestEnabled = enabled;
        emit HarvestConfigured(maxTokens, enabled);
    }
    /// @notice Only the Safe manages bounded operators; operators cannot appoint other operators.
    /// @param operator Nonzero routine operator, distinct from the fixed Safe authority.
    /// @param enabled Grant or revoke bounded collection permission.
    function setOperator(address operator, bool enabled) external onlySafe {
        if (operator == address(0) || operator == treasury) revert InvalidConfiguration();
        operators[operator] = enabled;
        emit OperatorSet(operator, enabled);
    }

    /// @inheritdoc IV2SupporterVault
    function deposit(
        uint256 tokens,
        uint256 minBasis,
        uint256 deadline
    ) external nonReentrant onlyNormal returns (uint256 id, uint256 basis) {
        basis = _deposit(SUPPORTER, tokens, minBasis, deadline);
        id = nextPositionId++;
        uint256 unlockAt = block.timestamp + LOCK_PERIOD;
        _positions[id] = Position(msg.sender, basis, unlockAt, false);
        emit PositionOpened(id, msg.sender, tokens, basis, unlockAt);
    }
    /// @inheritdoc IV2SupporterVault
    function depositProtocol(
        uint256 tokens,
        uint256 minBasis,
        uint256 deadline
    ) external nonReentrant onlyNormal returns (uint256 basis) {
        if (msg.sender != manager) revert Unauthorized();
        basis = _deposit(PROTOCOL, tokens, minBasis, deadline);
        emit ProtocolDeposited(tokens, basis);
    }
    /// @inheritdoc IV2SupporterVault
    function withdraw(
        uint256 id,
        uint256 minTokensOut,
        uint256 deadline
    ) external nonReentrant returns (uint256 tokens) {
        _deadline(deadline);
        Position storage p = _positions[id];
        _open(p);
        if (p.owner != msg.sender) revert Unauthorized();
        if (block.timestamp < p.unlockAt) revert PositionLocked();
        uint256 basis = p.basis;
        p.closed = true;
        tokens = _withdraw(SUPPORTER, basis, minTokensOut);
        _send(msg.sender, tokens);
        emit PositionClosed(id, msg.sender, basis, tokens, recoveryState == RecoveryState.Settlement);
        if (recoveryState == RecoveryState.Settlement) emit RecoveryClaimed(SUPPORTER, id, basis, tokens);
    }
    /// @inheritdoc IV2SupporterVault
    function withdrawProtocol(
        uint256 basis,
        uint256 minTokensOut,
        uint256 deadline
    ) external nonReentrant onlySafe returns (uint256 tokens) {
        _deadline(deadline);
        tokens = _withdraw(PROTOCOL, basis, minTokensOut);
        _send(treasury, tokens);
        emit ProtocolWithdrawn(basis, tokens, recoveryState == RecoveryState.Settlement);
        if (recoveryState == RecoveryState.Settlement) emit RecoveryClaimed(PROTOCOL, 0, basis, tokens);
    }
    /// @inheritdoc IV2SupporterVault
    function collectYield(uint8 which, uint256 maxTokens) external nonReentrant onlyNormal returns (uint256 tokens) {
        _checkBucket(which);
        if (msg.sender != treasury && !operators[msg.sender]) revert Unauthorized();
        if (!harvestEnabled) revert HarvestDisabled();
        if (maxTokens == 0 || maxTokens > maximumHarvest) revert InvalidAmount();
        _custody();
        _requireFresh();
        (uint256 n, uint256 d) = rateSnapshot();
        Bucket storage b = _buckets[which];
        tokens = Math.min(maxTokens, b.tokens - _reserve(b.basis, b.tokens, n, d));
        if (tokens == 0) return 0;
        b.tokens -= tokens;
        b.harvestedTokens += tokens;
        _yield(which, tokens);
        emit YieldCollected(which, tokens);
    }
    /// @inheritdoc IV2SupporterVault
    function repair(uint8 which, uint256 tokens) external nonReentrant onlyNormal {
        _checkBucket(which);
        _custody();
        _pull(tokens);
        _buckets[which].tokens += tokens;
        _buckets[which].repairTokens += tokens;
        emit Repaired(which, msg.sender, tokens);
    }
    /// @inheritdoc IV2SupporterVault
    function recognizeSurplus(uint8 which, uint256 tokens, bool isRepair) external nonReentrant onlySafe onlyNormal {
        _checkBucket(which);
        uint256 surplus = _custody() - _buckets[0].tokens - _buckets[1].tokens;
        if (tokens == 0 || tokens > surplus) revert InvalidAmount();
        if (!isRepair) {
            (uint256 n, uint256 d) = rateSnapshot();
            if (Math.mulDiv(_buckets[which].tokens, n, d) < _buckets[which].basis) revert Deficit();
        }
        _buckets[which].tokens += tokens;
        if (isRepair) _buckets[which].repairTokens += tokens;
        emit SurplusRecognized(which, tokens, isRepair);
    }

    /// @inheritdoc IV2SupporterVault
    function beginRecovery(bytes32 manifest) external nonReentrant onlySafe onlyNormal {
        if (manifest == bytes32(0)) revert InvalidConfiguration();
        recoveryState = RecoveryState.Custody;
        entriesEnabled = false;
        harvestEnabled = false;
        initialManifest = manifest;
        recoveryPositionBoundary = nextPositionId;
        recoveryInstance = keccak256(abi.encode(block.chainid, address(this), block.number, manifest, nextPositionId));
        uint256 expected = _buckets[0].tokens + _buckets[1].tokens;
        uint256 held = IERC20(asset).balanceOf(address(this));
        uint256 exported = Math.min(held, expected);
        bool shortage = held < expected;
        recoverySurplus = held - exported;
        uint256 supporterExport = shortage ? Math.mulDiv(exported, _buckets[0].tokens, expected) : _buckets[0].tokens;
        _snapshot(SUPPORTER, supporterExport);
        _snapshot(PROTOCOL, exported - supporterExport);
        _send(treasury, exported);
        emit RecoveryStarted(recoveryInstance, manifest, nextPositionId, recoverySurplus, exported, shortage);
    }
    /// @inheritdoc IV2SupporterVault
    function fundRecovery(uint8 which, uint256 tokens) external nonReentrant {
        _checkBucket(which);
        _requireCustodyState();
        RecoveryBucket storage r = _recovery[which];
        if (tokens > r.exportedTokens - r.returnedTokens) revert InvalidAmount();
        _pull(tokens);
        r.returnedTokens += tokens;
        emit RecoveryFunded(which, msg.sender, tokens, false);
    }
    /// @inheritdoc IV2SupporterVault
    function repairRecovery(uint8 which, uint256 tokens) external nonReentrant {
        _checkBucket(which);
        _requireCustodyState();
        _pull(tokens);
        _recovery[which].repairTokens += tokens;
        emit RecoveryFunded(which, msg.sender, tokens, true);
    }
    /// @inheritdoc IV2SupporterVault
    function fundRefundableRecovery(uint8 which, uint256 tokens) external nonReentrant onlySafe {
        _checkBucket(which);
        _requireCustodyState();
        RecoveryBucket storage r = _recovery[which];
        if (r.returnedTokens != r.exportedTokens) revert InvalidAmount();
        _pull(tokens);
        r.repairTokens += tokens;
        r.refundableRepairTokens += tokens;
        emit RecoveryRefundableFunded(which, msg.sender, tokens);
    }
    /// @notice Maximum principal budgets under one coherent canonical rate; returned backing is never counted twice.
    /// @return caps Supporter and protocol principal-token caps, in that order.
    function recoveryCaps() external view returns (uint256[2] memory caps) {
        (uint256 n, uint256 d) = rateSnapshot();
        for (uint8 i; i < 2; ++i) {
            RecoveryBucket storage r = _recovery[i];
            uint256 q = r.exportedTokens + r.repairTokens;
            uint256 b = r.snapshot.basis;
            if (b == 0) caps[i] = 0;
            else if (Math.mulDiv(q, n, d) < b) caps[i] = q;
            else caps[i] = Math.min(q, Math.mulDiv(b, d, n));
        }
    }
    /// @inheritdoc IV2SupporterVault
    function activateSettlement(uint256[2] calldata budgets, bytes32 manifest) external nonReentrant onlySafe {
        _requireCustodyState();
        uint256[2] memory caps = this.recoveryCaps();
        for (uint8 i; i < 2; ++i) {
            if (budgets[i] > caps[i]) revert InvalidBudget();
        }
        _activate(budgets, manifest, false);
    }
    /// @inheritdoc IV2SupporterVault
    function activateExceptionalSettlement(
        uint256[2] calldata budgets,
        bytes32 manifest
    ) external nonReentrant onlySafe {
        _requireCustodyState();
        // A revert in the success block is not caught: available valuation cannot silently select manual mode.
        // solhint-disable no-empty-blocks
        try this.recoveryCaps() returns (uint256[2] memory) {
            revert ValuationAvailable();
        } catch {
            // An unavailable canonical view is precisely the explicitly approved exceptional-classification condition.
        }
        // solhint-enable no-empty-blocks
        _activate(budgets, manifest, true);
    }
    /// @inheritdoc IV2SupporterVault
    function finalizeRecovery() external nonReentrant onlySafe {
        if (recoveryState != RecoveryState.Settlement) revert WrongState();
        if (_buckets[0].basis != 0 || _buckets[1].basis != 0) revert OutstandingLiabilities();
        _settlementCustody();
        recoveryState = RecoveryState.Settled;
        uint256[2] memory donation;
        uint256 refund;
        for (uint8 i; i < 2; ++i) {
            RecoveryBucket storage r = _recovery[i];
            uint256 funded = r.returnedTokens + r.repairTokens;
            uint256 unusedRepair = Math.min(r.refundableRepairTokens, funded - r.budget);
            refund += unusedRepair;
            donation[i] = funded - r.paidTokens - unusedRepair;
        }
        // Unassigned custody is neither principal nor repair refund; donate only after every claim closes.
        uint256 unassigned = IERC20(asset).balanceOf(address(this)) - donation[0] - donation[1] - refund;
        donation[0] += unassigned;
        _send(treasury, refund);
        _yield(SUPPORTER, donation[0]);
        _yield(PROTOCOL, donation[1]);
        emit RecoveryFinalized(recoveryInstance, donation[0], donation[1], refund);
    }
    /// @notice Rescue accidental noncore ERC20s only; native principal token rescue is never a routine operation.
    /// @param token Accidental ERC20 other than the fixed native custody asset.
    /// @param tokens Positive quantity sent only to the fixed treasury.
    function rescueNoncore(address token, uint256 tokens) external nonReentrant onlySafe {
        if (token == asset || token == address(0) || tokens == 0) revert InvalidAmount();
        IERC20(token).safeTransfer(treasury, tokens);
        emit NoncoreRescued(token, tokens);
    }

    function _deposit(uint8 which, uint256 tokens, uint256 minBasis, uint256 deadline) private returns (uint256 basis) {
        _deadline(deadline);
        if (!entriesEnabled) revert EntriesDisabled();
        _custody();
        _requireFresh();
        (uint256 n, uint256 d) = rateSnapshot();
        if (
            Math.mulDiv(_buckets[0].tokens, n, d) < _buckets[0].basis ||
            Math.mulDiv(_buckets[1].tokens, n, d) < _buckets[1].basis
        ) revert Deficit();
        _pull(tokens);
        basis = Math.mulDiv(tokens, n, d);
        if (basis == 0 || basis < minimumBasis || Math.mulDiv(basis, d, n) == 0) revert InvalidAmount();
        if (basis < minBasis) revert Slippage();
        Bucket storage b = _buckets[which];
        b.tokens += tokens;
        b.basis += basis;
        b.enteredBasis += basis;
    }
    function _withdraw(uint8 which, uint256 basis, uint256 minimum) private returns (uint256 tokens) {
        Bucket storage b = _buckets[which];
        if (basis == 0 || basis > b.basis) revert InvalidAmount();
        if (recoveryState == RecoveryState.Normal) {
            _custody();
            (uint256 n, uint256 d) = rateSnapshot();
            tokens = _principalTokens(b, basis, n, d);
            if (tokens == 0) revert InvalidAmount();
            b.tokens -= tokens;
            uint256 returnedBasis = Math.mulDiv(tokens, n, d);
            if (returnedBasis < basis) {
                uint256 loss = basis - returnedBasis;
                b.realizedLossBasis += loss;
                emit RealizedLoss(which, basis, returnedBasis, loss);
            }
        } else if (recoveryState == RecoveryState.Settlement) {
            _settlementCustody();
            tokens = _settlementTokens(which, basis);
            _recovery[which].paidTokens += tokens;
            _recovery[which].closedBasis += basis;
        } else revert WrongState();
        if (tokens < minimum) revert Slippage();
        b.basis -= basis;
        b.removedBasis += basis;
        b.principalTokensPaid += tokens;
    }
    function _principalTokens(Bucket storage b, uint256 basis, uint256 n, uint256 d) private view returns (uint256) {
        if (Math.mulDiv(b.tokens, n, d) >= b.basis) return Math.mulDiv(basis, d, n);
        if (basis == b.basis) return b.tokens;
        return Math.mulDiv(b.tokens, basis, b.basis);
    }
    function _reserve(uint256 basis, uint256 tokens, uint256 n, uint256 d) private pure returns (uint256) {
        if (basis == 0) return 0;
        if (Math.mulDiv(tokens, n, d) < basis) return tokens;
        return Math.mulDiv(basis, d, n, Math.Rounding.Ceil);
    }
    function _snapshot(uint8 which, uint256 exported) private {
        RecoveryBucket storage r = _recovery[which];
        r.snapshot = _buckets[which];
        r.exportedTokens = exported;
        _buckets[which].tokens = 0;
        bool available;
        uint256 value;
        // solhint-disable no-empty-blocks
        try this.canonicalValue(r.snapshot.tokens) returns (uint256 v) {
            available = true;
            value = v;
        } catch {
            // Missing valuation must not block exporting the exact accounted native-token custody.
        }
        // solhint-enable no-empty-blocks
        emit RecoveryBucketSnapshot(
            recoveryInstance,
            which,
            r.snapshot.basis,
            r.snapshot.tokens,
            exported,
            available,
            value
        );
    }
    function _activate(uint256[2] calldata budgets, bytes32 manifest, bool exceptional) private {
        if (manifest == bytes32(0) || manifest == initialManifest) revert InvalidConfiguration();
        for (uint8 i; i < 2; ++i) {
            RecoveryBucket storage r = _recovery[i];
            if ((r.snapshot.basis == 0 && budgets[i] != 0) || budgets[i] > r.exportedTokens + r.repairTokens)
                revert InvalidBudget();
            if (r.returnedTokens + r.repairTokens < budgets[i]) revert UnfundedSettlement();
            r.budget = budgets[i];
        }
        _settlementCustody();
        settlementManifest = manifest;
        exceptionalSettlement = exceptional;
        recoveryState = RecoveryState.Settlement;
        emit SettlementActivated(recoveryInstance, manifest, exceptional, budgets[0], budgets[1]);
    }
    function _settlementTokens(uint8 which, uint256 basis) private view returns (uint256) {
        RecoveryBucket storage r = _recovery[which];
        return Math.mulDiv(r.budget, basis, r.snapshot.basis);
    }
    function _settlementCustody() private view {
        uint256 required;
        for (uint8 i; i < 2; ++i)
            required += _recovery[i].returnedTokens + _recovery[i].repairTokens - _recovery[i].paidTokens;
        if (IERC20(asset).balanceOf(address(this)) < required) revert CustodyShortfall();
    }
    function _custody() private view returns (uint256 held) {
        held = IERC20(asset).balanceOf(address(this));
        if (held < _buckets[0].tokens + _buckets[1].tokens) revert CustodyShortfall();
    }
    function _pull(uint256 tokens) private {
        if (tokens == 0) revert InvalidAmount();
        uint256 beforeBalance = IERC20(asset).balanceOf(address(this));
        IERC20(asset).safeTransferFrom(msg.sender, address(this), tokens);
        uint256 afterBalance = IERC20(asset).balanceOf(address(this));
        if (afterBalance < beforeBalance || afterBalance - beforeBalance != tokens) revert UnexpectedTokenDelta();
    }
    function _send(address recipient, uint256 tokens) private {
        if (tokens == 0) return;
        uint256 beforeBalance = IERC20(asset).balanceOf(address(this));
        uint256 beforeRecipient = IERC20(asset).balanceOf(recipient);
        IERC20(asset).safeTransfer(recipient, tokens);
        uint256 afterBalance = IERC20(asset).balanceOf(address(this));
        uint256 afterRecipient = IERC20(asset).balanceOf(recipient);
        if (
            afterBalance > beforeBalance ||
            beforeBalance - afterBalance != tokens ||
            afterRecipient < beforeRecipient ||
            afterRecipient - beforeRecipient != tokens
        ) revert UnexpectedTokenDelta();
    }
    function _yield(uint8 which, uint256 tokens) private {
        if (tokens == 0) return;
        _send(manager, tokens);
        IV2VaultYieldReceiver(manager).onYieldReceived(which, tokens);
    }
    function _requireCustodyState() private view {
        if (recoveryState != RecoveryState.Custody) revert WrongState();
    }
    function _checkBucket(uint8 which) private pure {
        if (which > PROTOCOL) revert InvalidBucket();
    }
    function _deadline(uint256 deadline) private view {
        if (block.timestamp > deadline) revert Expired();
    }
    function _open(Position storage p) private view {
        if (p.owner == address(0) || p.closed) revert ClosedPosition();
    }
    /// @dev Safe-only UUPS authorization; the bounded operator mapping cannot authorize upgrades.
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlySafe {
        // Authorization is entirely enforced by the fixed Safe modifier, never by the bounded operator mapping.
    }
    /// @dev Return one coherent protocol-reference rate; zero numerator is a successful impairment observation.
    function _readRate() internal view virtual returns (uint256 numerator, uint256 denominator);
    /// @dev Additional entry/harvest freshness checks, deliberately absent from in-kind exits.
    function _requireFresh() internal view virtual;
}
