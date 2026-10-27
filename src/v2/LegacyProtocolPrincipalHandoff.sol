// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IYieldManager } from "src/interfaces/IYieldManager.sol";
import { IEthToBoldRouter } from "src/interfaces/IEthToBoldRouter.sol";
import { ILegacyProtocolPrincipalHandoff } from "src/interfaces/v2/ILegacyProtocolPrincipalHandoff.sol";
import { LegacyIntakeStopper } from "src/v2/LegacyIntakeStopper.sol";

/// @title Legacy adapter accounting views
/// @notice The deployed adapter's native accounting and underlying Beefy share identity.
/// @author Seba Protocol
interface IHandoffAdapter {
    /// @notice Read remaining synthetic principal value in the adapter's native accounting units.
    /// @return Remaining adapter principal value, not ETH wei.
    function principalValue() external view returns (uint256);
    /// @notice Read Beefy-share atoms attributed to remaining principal.
    /// @return Accounted principal shares.
    function principalShares() external view returns (uint256);
    /// @notice Read the adapter's fixed Beefy share token identity.
    /// @return Underlying Beefy-token address.
    function beefy() external view returns (address);
}

/// @title Legacy pool routing view
/// @notice Only the existing pool pointer is inspected; this handoff cannot change it.
/// @author Seba Protocol
interface IHandoffPool {
    /// @notice Read the manager currently receiving pool protocol rewards.
    /// @return Active yield-manager address.
    function yieldManager() external view returns (address);
}

/// @title Safe migration-policy views
/// @notice Safe security state used by the narrowly typed cutover assertions.
/// @author Seba Protocol
interface IHandoffSafe {
    /// @notice Read the Safe's ordered owner list.
    /// @return Ordered owners whose full ABI encoding is committed in the approved snapshot.
    function getOwners() external view returns (address[] memory);
    /// @notice Read the Safe's required signature count.
    /// @return Current transaction threshold.
    function getThreshold() external view returns (uint256);
    /// @notice Inspect one page of enabled Safe modules.
    /// @param start Module-list cursor; address(1) is the Safe sentinel.
    /// @param size Maximum number of modules to return.
    /// @return Page of enabled modules.
    /// @return Next cursor, or address(1) when the list ends.
    function getModulesPaginated(address start, uint256 size) external view returns (address[] memory, address);
    /// @notice Read Safe storage for the exact guard-slot assertion.
    /// @param offset First storage-slot index.
    /// @param length Number of consecutive 32-byte slots.
    /// @return Concatenated raw storage words.
    function getStorageAt(uint256 offset, uint256 length) external view returns (bytes memory);
}

/// @title New-manager migration and accounting interface
/// @notice Exact new-manager import and accounting views, not an arbitrary execution API.
/// @author Seba Protocol
interface IHandoffDestination {
    /// @notice Read the fixed governance Safe.
    /// @return Treasury Safe address.
    function treasury() external view returns (address);
    /// @notice Read the protocol-reward source.
    /// @return SebaPool address.
    function sebaPool() external view returns (address);
    /// @notice Read the BOLD integration identity.
    /// @return BOLD-token address.
    function bold() external view returns (address);
    /// @notice Read the donation-vault integration identity.
    /// @return sBOLD-token address.
    function sBold() external view returns (address);
    /// @notice Read the existing graduation/reward vault identity.
    /// @return PYB SEBA vault address.
    function pybSeba() external view returns (address);
    /// @notice Read whether pool protocol-reward intake is enabled.
    /// @return Current intake mode.
    function intakeEnabled() external view returns (bool);
    /// @notice Read whether bounded investment and harvest execution is enabled.
    /// @return Current execution mode.
    function executionEnabled() external view returns (bool);
    /// @notice Read whether same-token emergency buffer recovery has occurred.
    /// @return Terminal buffer-recovery state.
    function buffersRecovered() external view returns (bool);
    /// @notice Read an accounted protocol ETH bucket.
    /// @param purpose Bucket index: 0 direct donation, 1 rETH investment, 2 ysyBOLD investment.
    /// @return ETH wei in that bucket.
    function pendingEth(uint256 purpose) external view returns (uint256);
    /// @notice Read BOLD awaiting donation-vault conversion.
    /// @return Accounted BOLD atoms.
    function pendingBold() external view returns (uint256);
    /// @notice Read sBOLD awaiting donation to PYB SEBA.
    /// @return Accounted sBOLD atoms.
    function pendingSBold() external view returns (uint256);
    /// @notice Read harvested native receipt tokens awaiting donation conversion.
    /// @param leg Asset leg: 0 rETH, 1 ysyBOLD.
    /// @param bucket Principal category: 0 supporters, 1 protocol.
    /// @return Accounted receipt-token atoms.
    function harvestInventory(uint8 leg, uint8 bucket) external view returns (uint256);
    /// @notice Read the configured rETH share of protocol investment capital.
    /// @return Investment allocation in basis points.
    function rethBps() external view returns (uint16);
    /// @notice Read the configured ysyBOLD share of protocol investment capital.
    /// @return Investment allocation in basis points.
    function ysyBoldBps() external view returns (uint16);
    /// @notice Read the exact armed one-time handoff contract.
    /// @return Authorized legacy handoff address.
    function legacyHandoff() external view returns (address);
    /// @notice Read the exact armed legacy ETH budget.
    /// @return Expected import in ETH wei.
    function legacyExpectedEth() external view returns (uint256);
    /// @notice Read the armed legacy import deadline.
    /// @return Inclusive deadline in Unix seconds.
    function legacyExpiry() external view returns (uint256);
    /// @notice Read the approved migration-manifest commitment.
    /// @return Reviewed offchain release manifest hash.
    function legacyManifest() external view returns (bytes32);
    /// @notice Read whether legacy protocol principal has already been imported.
    /// @return One-time import completion flag.
    function legacyImported() external view returns (bool);
    /// @notice Import exact approved ETH solely from the armed handoff; no fresh-reward donation split applies.
    function importLegacyPrincipal() external payable;
}

/// @title Exact, atomic second-stage legacy protocol-principal handoff
/// @notice Deployed legacy YieldManager accepts a zero return only on its admin principal-deposit path.
/// @dev EIP-1153 coordinates precheck/import inside one transaction. The reviewed Safe MultiSend must still include
/// the final pool-pointer update and postassertion. The separately completed Stage A exit is never rolled back by this
/// contract: its exact ETH remains in the old manager behind the canonical intake stopper until Stage B succeeds.
/// @author Seba Protocol
contract LegacyProtocolPrincipalHandoff is ILegacyProtocolPrincipalHandoff {
    // Public getter names deliberately match the shared interface.
    // solhint-disable immutable-vars-naming
    /// @notice Fixed legacy manager and sole principal sender.
    address public immutable override oldManager;
    /// @notice Fixed new-manager proxy receiving the one-time import.
    address public immutable override destination;
    /// @notice Fixed Safe authorized to run pre- and post-migration assertions.
    address public immutable override treasury;
    /// @notice Exact approved import budget in ETH wei, not a slippage minimum.
    uint256 public immutable override expectedEth;
    /// @notice Inclusive final permitted timestamp in Unix seconds.
    uint256 public immutable override expiry;
    /// @notice Chain ID captured at construction; migration on another chain reverts.
    uint256 public immutable override chainId;
    // solhint-enable immutable-vars-naming
    /// @notice Commitment to every exact constructor configuration field.
    bytes32 public immutable CONFIGURATION_HASH;
    bytes32 private immutable OLD_MANAGER_CODE;
    bytes32 private immutable OLD_ADAPTER_CODE;
    bytes32 private immutable OLD_ROUTER_CODE;
    bytes32 private immutable POOL_CODE;
    bytes32 private immutable STAGING_VAULT_CODE;
    address private immutable BOLD;
    address private immutable SBOLD;
    address private immutable BEEFY;
    Configuration private _configuration;
    /// @inheritdoc ILegacyProtocolPrincipalHandoff
    bool public override used;
    bool private transient _preflight;
    bool private transient _imported;
    uint256 private transient _destinationEthBefore;

    /// @notice Store the exited Stage A snapshot. This contract has no configuration setters or upgrade path.
    /// @param c Exact reviewed contract identities, legacy accounting, Safe policy and migration budget.
    constructor(Configuration memory c) {
        if (
            c.oldManager.code.length == 0 ||
            c.destination.code.length == 0 ||
            c.treasury.code.length == 0 ||
            c.pool.code.length == 0 ||
            c.oldVault.code.length == 0 ||
            c.oldRouter.code.length == 0 ||
            c.oldManager == c.destination ||
            c.expectedEth == 0 ||
            c.expiry < block.timestamp ||
            c.oldPrincipal != 0 ||
            c.oldIdleEth != c.expectedEth ||
            c.safeOwnersHash == bytes32(0) ||
            c.safeThreshold == 0 ||
            c.rethBps > 10_000 ||
            c.manifest == bytes32(0)
        ) revert InvalidConfiguration();
        bytes32 stagingCode = keccak256(type(LegacyIntakeStopper).runtimeCode);
        if (c.stagingVault.codehash != stagingCode) revert InvalidConfiguration();
        oldManager = c.oldManager;
        destination = c.destination;
        treasury = c.treasury;
        expectedEth = c.expectedEth;
        expiry = c.expiry;
        chainId = block.chainid;
        _configuration = c;
        CONFIGURATION_HASH = keccak256(abi.encode(c));
        OLD_MANAGER_CODE = c.oldManager.codehash;
        OLD_ADAPTER_CODE = c.oldVault.codehash;
        OLD_ROUTER_CODE = c.oldRouter.codehash;
        POOL_CODE = c.pool.codehash;
        STAGING_VAULT_CODE = stagingCode;
        BOLD = address(IYieldManager(c.oldManager).BOLD());
        SBOLD = address(IYieldManager(c.oldManager).sBOLD());
        BEEFY = IHandoffAdapter(c.oldVault).beefy();
        if (BOLD.code.length == 0 || SBOLD.code.length == 0 || BEEFY.code.length == 0) revert InvalidConfiguration();
    }

    /// @inheritdoc ILegacyProtocolPrincipalHandoff
    function configuration() external view returns (Configuration memory) {
        return _configuration;
    }

    /// @inheritdoc ILegacyProtocolPrincipalHandoff
    function assertPreMigration() external {
        _safeCaller();
        _timeAndCode();
        _safePolicy();
        if (used) revert AlreadyUsed();
        IYieldManager old = IYieldManager(oldManager);
        if (
            address(old.yieldVault()) != _configuration.stagingVault ||
            old.principalValue() != _configuration.oldPrincipal ||
            address(oldManager).balance != _configuration.oldIdleEth ||
            IHandoffAdapter(_configuration.oldVault).principalValue() != _configuration.adapterPrincipal ||
            IHandoffAdapter(_configuration.oldVault).principalShares() != _configuration.adapterShares ||
            IERC20(BEEFY).balanceOf(_configuration.oldVault) != _configuration.actualBeefyShares
        ) revert InvalidState();
        _legacyCommon();
        _destinationReady();
        _destinationEthBefore = destination.balance;
        _preflight = true;
        emit PreMigrationChecked(_configuration.manifest, CONFIGURATION_HASH, destination.balance);
    }

    /// @inheritdoc ILegacyProtocolPrincipalHandoff
    function deposit() external payable returns (uint256) {
        if (msg.sender != oldManager) revert Unauthorized();
        _timeAndCode();
        if (used) revert AlreadyUsed();
        if (!_preflight) revert MissingAtomicPreflight();
        if (msg.value != expectedEth) revert WrongAmount();
        IYieldManager old = IYieldManager(oldManager);
        if (address(old.yieldVault()) != address(this) || old.principalValue() != 0) revert InvalidState();
        _legacyCommon();
        _destinationReady();
        _safePolicy();
        _preflight = false;
        used = true;
        _imported = true;
        IHandoffDestination(destination).importLegacyPrincipal{ value: msg.value }();
        emit PrincipalHandedOff(oldManager, destination, msg.value);
        // Normal old public depositFunds() MUST reject this zero return and roll back the entire import.
        return 0;
    }

    /// @inheritdoc ILegacyProtocolPrincipalHandoff
    function assertPostMigration() external {
        _safeCaller();
        _timeAndCode();
        _safePolicy();
        if (!used || !_imported) revert MissingAtomicPreflight();
        IYieldManager old = IYieldManager(oldManager);
        IHandoffDestination next = IHandoffDestination(destination);
        uint256 r = Math.mulDiv(expectedEth, _configuration.rethBps, 10_000);
        if (
            IHandoffPool(_configuration.pool).yieldManager() != destination ||
            address(old.yieldVault()) != address(this) ||
            old.principalValue() != 0 ||
            oldManager.balance != 0 ||
            !next.legacyImported() ||
            !next.intakeEnabled() ||
            next.executionEnabled() ||
            next.buffersRecovered() ||
            next.pendingEth(0) != 0 ||
            next.pendingEth(1) != r ||
            next.pendingEth(2) != expectedEth - r ||
            destination.balance != _destinationEthBefore + expectedEth
        ) revert InvalidState();
        _noLegacyClaims();
        _conversionsClear();
        _destinationIdentities();
        _imported = false;
        emit ResidualSurplusObserved(
            _configuration.manifest,
            _configuration.oldRouter.balance,
            IERC20(BOLD).balanceOf(oldManager),
            IERC20(SBOLD).balanceOf(oldManager),
            IERC20(BOLD).balanceOf(_configuration.oldRouter)
        );
        emit PostMigrationChecked(
            _configuration.manifest,
            IHandoffAdapter(_configuration.oldVault).principalValue(),
            IHandoffAdapter(_configuration.oldVault).principalShares(),
            IERC20(BEEFY).balanceOf(_configuration.oldVault)
        );
    }

    /// @inheritdoc ILegacyProtocolPrincipalHandoff
    function claimYield() external pure {
        revert UnsupportedOperation();
    }

    /// @inheritdoc ILegacyProtocolPrincipalHandoff
    function retrievePrincipal(uint256) external pure {
        revert UnsupportedOperation();
    }

    /// @dev Typed legacy identity, order and zero-live-claim assertions; no arbitrary external execution.
    function _legacyCommon() private view {
        IYieldManager old = IYieldManager(oldManager);
        if (
            old.sebaPool() != _configuration.pool ||
            address(old.router()) != _configuration.oldRouter ||
            IHandoffPool(_configuration.pool).yieldManager() != oldManager
        ) revert InvalidState();
        _noLegacyClaims();
        _conversionsClear();
    }

    /// @dev Deposit counter equality also catches intervening deposits that were subsequently withdrawn.
    function _noLegacyClaims() private view {
        IYieldManager old = IYieldManager(oldManager);
        if (old.depositId() != _configuration.oldDepositId) revert InvalidState();
        for (uint256 id = 1; id <= _configuration.oldDepositId; ++id) {
            (, , uint256 amount, ) = old.deposits(id);
            if (amount != 0) revert ActiveLegacyClaim(id);
        }
    }

    /// @dev A zero manager UID alone does not prove actual router/order/token custody is reconciled.
    /// Only the four explicitly approved, disclosed residual balances may remain unmigrated.
    function _conversionsClear() private view {
        IYieldManager old = IYieldManager(oldManager);
        (, , , bool active, ) = IEthToBoldRouter(_configuration.oldRouter).order();
        if (
            old.pendingBoldConversion() != 0 ||
            old.activeRouterUid() != bytes32(0) ||
            active ||
            _configuration.oldRouter.balance > _configuration.maximumRouterEth ||
            IERC20(BOLD).balanceOf(oldManager) > _configuration.maximumOldBold ||
            IERC20(SBOLD).balanceOf(oldManager) > _configuration.maximumOldSBold ||
            IERC20(BOLD).balanceOf(_configuration.oldRouter) > _configuration.maximumRouterBold
        ) revert InvalidState();
    }

    /// @dev Require a separately armed, empty protocol destination with the approved fixed import weights.
    function _destinationReady() private view {
        IHandoffDestination next = IHandoffDestination(destination);
        _destinationIdentities();
        if (
            next.legacyImported() ||
            next.intakeEnabled() ||
            next.executionEnabled() ||
            next.buffersRecovered() ||
            next.pendingBold() != 0 ||
            next.pendingSBold() != 0
        ) revert InvalidState();
        for (uint256 i; i < 3; ++i) if (next.pendingEth(i) != 0) revert InvalidState();
        for (uint8 leg; leg < 2; ++leg)
            for (uint8 bucket; bucket < 2; ++bucket) {
                if (next.harvestInventory(leg, bucket) != 0) revert InvalidState();
            }
    }

    /// @dev Validate the exact reviewed import authority, asset identities and allocation, before and after cutover.
    function _destinationIdentities() private view {
        IHandoffDestination next = IHandoffDestination(destination);
        if (
            next.treasury() != treasury ||
            next.sebaPool() != _configuration.pool ||
            next.bold() != BOLD ||
            next.sBold() != SBOLD ||
            next.pybSeba() != address(IYieldManager(oldManager).sebaVault()) ||
            next.legacyHandoff() != address(this) ||
            next.legacyExpectedEth() != expectedEth ||
            next.legacyExpiry() != expiry ||
            next.legacyManifest() != _configuration.manifest ||
            next.rethBps() != _configuration.rethBps ||
            uint256(next.ysyBoldBps()) + next.rethBps() != 10_000
        ) revert InvalidState();
    }

    /// @dev Safe owners/order, threshold, no modules and no guard are exact approved release assumptions.
    function _safePolicy() private view {
        IHandoffSafe safe = IHandoffSafe(treasury);
        address[] memory owners = safe.getOwners();
        if (
            keccak256(abi.encode(owners)) != _configuration.safeOwnersHash ||
            safe.getThreshold() != _configuration.safeThreshold ||
            _configuration.safeThreshold > owners.length
        ) revert InvalidState();
        (address[] memory modules, address next) = safe.getModulesPaginated(address(1), 1);
        bytes memory guard = safe.getStorageAt(0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8, 1);
        if (modules.length != 0 || next != address(1) || guard.length != 32 || abi.decode(guard, (uint256)) != 0)
            revert InvalidState();
    }

    /// @dev Code identity is captured from the independently verified reviewed deployment at construction.
    function _timeAndCode() private view {
        if (block.chainid != chainId) revert WrongChain();
        if (block.timestamp > expiry) revert Expired();
        if (
            oldManager.codehash != OLD_MANAGER_CODE ||
            _configuration.oldVault.codehash != OLD_ADAPTER_CODE ||
            _configuration.oldRouter.codehash != OLD_ROUTER_CODE ||
            _configuration.pool.codehash != POOL_CODE ||
            _configuration.stagingVault.codehash != STAGING_VAULT_CODE
        ) revert InvalidState();
    }

    /// @dev Only the verified Safe may mark the pre- and post-boundaries of the approved cutover batch.
    function _safeCaller() private view {
        if (msg.sender != treasury) revert Unauthorized();
    }
}
