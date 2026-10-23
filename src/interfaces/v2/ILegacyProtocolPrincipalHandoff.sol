// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title One-shot legacy protocol-principal cutover assertions
/// @notice This is not a generic executor, vault, fund sweep or public migration portal.
/// @author Seba Protocol
interface ILegacyProtocolPrincipalHandoff {
    /// @notice Exact Safe-reviewed migration snapshot; all amounts retain their named native units.
    /// @dev Stage A must already have exited: oldPrincipal is zero and oldIdleEth equals positive expectedEth.
    /// oldVault identifies the original Beefy adapter's unswept residue; stagingVault is the canonical intake stopper.
    struct Configuration {
        address oldManager;
        address destination;
        address treasury;
        address pool;
        address oldVault;
        address stagingVault;
        address oldRouter;
        uint256 expectedEth;
        uint256 expiry;
        uint256 oldPrincipal;
        uint256 oldDepositId;
        uint256 adapterPrincipal;
        uint256 adapterShares;
        uint256 actualBeefyShares;
        uint256 oldIdleEth;
        bytes32 safeOwnersHash;
        uint256 safeThreshold;
        uint16 rethBps;
        bytes32 manifest;
    }

    error Unauthorized();
    error InvalidConfiguration();
    error InvalidState();
    error Expired();
    error AlreadyUsed();
    error WrongChain();
    error MissingAtomicPreflight();
    error WrongAmount();
    error ActiveLegacyClaim(uint256 id);
    error UnsupportedOperation();

    /// @notice The approved pre-migration snapshot passed within the current atomic transaction.
    /// @param manifest Commitment to the reviewed offchain release and reconciliation manifest.
    /// @param configurationHash Commitment to every constructor Configuration field.
    /// @param destinationEthBefore Actual new-manager ETH wei before the one-time import, including unassigned dust.
    event PreMigrationChecked(
        bytes32 indexed manifest,
        bytes32 indexed configurationHash,
        uint256 destinationEthBefore
    );
    /// @notice Exact approved protocol capital was forwarded once to the new manager.
    /// @param oldManager Sole authorized legacy sender.
    /// @param destination Fixed new-manager proxy.
    /// @param ethAmount Exact approved ETH wei imported; not the old adapter's synthetic principal units.
    event PrincipalHandedOff(address indexed oldManager, address indexed destination, uint256 ethAmount);
    /// @notice Final pointer and accounting checks passed; legacy adapter rounding residue is disclosed, not swept.
    /// @param manifest Commitment to the reviewed offchain release and reconciliation manifest.
    /// @param residualAdapterPrincipal Remaining old adapter native principal-value units.
    /// @param residualAdapterShares Remaining old adapter accounted Beefy-share atoms.
    /// @param residualBeefyShares Remaining actual Beefy-token atoms held by the old adapter.
    event PostMigrationChecked(
        bytes32 indexed manifest,
        uint256 residualAdapterPrincipal,
        uint256 residualAdapterShares,
        uint256 residualBeefyShares
    );

    /// @notice Fixed new manager proxy authorized to receive exactly expectedEth.
    /// @return Authorized new-manager proxy address.
    function destination() external view returns (address);
    /// @notice Fixed legacy manager; no other caller may forward capital.
    /// @return Authorized legacy-manager address.
    function oldManager() external view returns (address);
    /// @notice Fixed governance Safe that runs the typed assertions.
    /// @return Approved Safe address.
    function treasury() external view returns (address);
    /// @notice Exact approved ETH amount, not a slippage minimum or quote promise.
    /// @return Expected import amount in ETH wei.
    function expectedEth() external view returns (uint256);
    /// @notice Final permitted timestamp, inclusive.
    /// @return Approved expiry in Unix seconds.
    function expiry() external view returns (uint256);
    /// @notice Deployment chain; changing chains invalidates the operation.
    /// @return Chain ID captured at construction.
    function chainId() external view returns (uint256);
    /// @notice True after the only successful principal import.
    /// @return Whether the one-time import has completed.
    function used() external view returns (bool);
    /// @notice Immutable reviewed snapshot and initial configuration commitment.
    /// @return Complete constructor configuration; no setter exists.
    function configuration() external view returns (Configuration memory);
    /// @notice Safe-only check of the exited, stopped legacy state; authorizes import only in this EVM transaction.
    function assertPreMigration() external;
    /// @notice Old-manager-only exact forwarding; deliberately returns zero to avoid duplicating legacy principal.
    /// @return Always zero, causing ordinary legacy public deposits to revert atomically.
    function deposit() external payable returns (uint256);
    /// @notice Safe-only final pointer/accounting checks in the same atomic cutover transaction.
    function assertPostMigration() external;
    /// @notice Unsupported: no strategy yield or principal remains in this handoff.
    function claimYield() external;
    /// @notice Unsupported: this handoff cannot redeem principal or pay users.
    /// @param amount Ignored principal amount; every call reverts.
    function retrievePrincipal(uint256 amount) external;
}
