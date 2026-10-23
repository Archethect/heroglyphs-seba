// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Seba V2 protocol capital and recognized-yield coordinator
/// @author Seba contributors
/// @notice Public supporter positions live in the two native-token vaults, not here.
interface IYieldManagerV2 {
    /// @notice Fixed identities checked again by deployment preflight against the selected chain.
    struct Initialization {
        address treasury;
        address operator;
        address pool;
        address bold;
        address sBold;
        address pybSeba;
        address reth;
        address ysyBold;
    }

    error Unauthorized();
    error InvalidConfiguration();
    error InvalidAmount();
    error InvalidLeg();
    error InvalidBucket();
    error IntakeDisabled();
    error ExecutionDisabled();
    error BuffersAlreadyRecovered();
    error InvalidTokenDelta();
    error InsufficientOutput();
    error Expired();
    error InvalidImport();
    error CoreAsset();
    error TransferFailed();

    /// @notice Fixed production identities were initialized atomically in the proxy.
    /// @param pool Sole source of fresh reward ETH.
    /// @param treasury Verified Safe administration, upgrade and recovery authority.
    /// @param bold Fixed BOLD reward token.
    /// @param sBold Fixed BOLD-denominated reward shares.
    /// @param pybSeba Existing validator reward-share system receiving sBOLD top-ups.
    /// @param reth Fixed rETH investment/carry token.
    /// @param ysyBold Fixed ysyBOLD investment/carry token.
    event ManagerInitialized(
        address indexed pool,
        address indexed treasury,
        address bold,
        address sBold,
        address pybSeba,
        address reth,
        address ysyBold
    );
    /// @notice Native vaults were bound once after reciprocal identity validation.
    /// @param rethVault rETH-native proxy, accounting principal in ETH wei.
    /// @param ysyBoldVault ysyBOLD-native proxy, accounting principal in yBOLD units.
    event VaultsBound(address indexed rethVault, address indexed ysyBoldVault);
    /// @notice Safe changed only fresh pool-intake permission.
    /// @param enabled New intake flag; recovery cannot be undone by enabling it.
    event IntakeSet(bool enabled);
    /// @notice Future invested-half weights changed without rebalancing existing assets or assigned cash.
    /// @param rethBps rETH share of future invested capital, in basis points.
    /// @param ysyBoldBps ysyBOLD share of future invested capital; weights sum to 10,000.
    /// @param version Monotonically increasing assignment-configuration version.
    event FutureWeightsSet(uint16 rethBps, uint16 ysyBoldBps, uint64 version);
    /// @notice A fresh reward receipt was assigned without interacting with any venue.
    /// @param totalEth Received ETH wei.
    /// @param rewardEth Direct-reward ETH wei, floor(totalEth/2).
    /// @param rethEth Invested ETH wei assigned to rETH under this version.
    /// @param ysyBoldEth Remaining invested ETH wei assigned to ysyBOLD.
    /// @param version Future-weight version effective for this receipt only.
    event PoolFundsAssigned(uint256 totalEth, uint256 rewardEth, uint256 rethEth, uint256 ysyBoldEth, uint64 version);
    /// @notice Safe configured a typed fixed-route executor and manager-side operation caps.
    /// @param executor Verified executor bound to this manager and treasury.
    /// @param maxEth Maximum ETH wei per authorized ETH-consuming route.
    /// @param maxReth Maximum rETH base units per authorized carry conversion.
    /// @param maxYsy Maximum ysyBOLD base units per authorized carry conversion.
    event ExecutionConfigured(address indexed executor, uint256 maxEth, uint256 maxReth, uint256 maxYsy);
    /// @notice Safe changed automated execution permission independently from pool intake.
    /// @param enabled New execution flag; cannot reopen a recovered manager.
    event ExecutionSet(bool enabled);
    /// @notice Safe granted or revoked bounded routine maintenance.
    /// @param operator Routine backend/operator address, never a grant of upgrade authority.
    /// @param enabled Whether bounded maintenance is authorized.
    event OperatorSet(address indexed operator, bool enabled);
    /// @notice Assigned ETH was converted and actual acquired backing credited to one protocol bucket.
    /// @param leg Zero rETH or one ysyBOLD.
    /// @param ethSpent Actual debited ETH wei, not an intact native-basis guarantee after acquisition costs.
    /// @param tokens Actual rETH/ysyBOLD base units acquired and deposited.
    /// @param basis Actual ETH-wei/yBOLD-unit principal credited by that leg's vault.
    event ProtocolDeployed(uint8 indexed leg, uint256 ethSpent, uint256 tokens, uint256 basis);
    /// @notice A configured leaf atomically transferred recognized carry into classified manager inventory.
    /// @param leg Zero rETH or one ysyBOLD, derived from the authenticated caller.
    /// @param bucket Original supporter zero or protocol one capital source.
    /// @param tokens Exact native carry-token base units, not completed validator income.
    event HarvestReceived(uint8 indexed leg, uint8 indexed bucket, uint256 tokens);
    /// @notice One classified reward source was converted into BOLD without a second 50/50 split.
    /// @param source Zero direct ETH rewards, one rETH carry, two ysyBOLD carry.
    /// @param bucket Carry source bucket; zero is only a source marker for direct ETH, not supporter capital.
    /// @param input Exact ETH wei or source-native token base units consumed.
    /// @param boldOut Actual BOLD base units received and classified.
    event RewardsConverted(uint8 indexed source, uint8 indexed bucket, uint256 input, uint256 boldOut);
    /// @notice Classified BOLD was converted into actual sBOLD shares, not yet donated.
    /// @param boldIn Exact BOLD base units consumed.
    /// @param sBoldOut Actual sBOLD share base units received.
    event SBoldMinted(uint256 boldIn, uint256 sBoldOut);
    /// @notice Existing pybSeba actually received classified sBOLD; canonical completed-donation attribution.
    /// @param sBoldAmount Exact sBOLD base units moved to pybSeba; do not count prior harvest/conversion again.
    event DonationCompleted(uint256 sBoldAmount);
    /// @notice Safe irreversibly armed one exact reviewed legacy import candidate.
    /// @param handoff Immutable one-shot source adapter.
    /// @param expectedEth Exact required ETH wei, not legacy adapter-native principal units.
    /// @param expiry Latest permitted import timestamp.
    /// @param weightVersion Invested-half weights frozen while this import remains pending.
    /// @param manifest Published exact-source/amount/destination migration approval commitment.
    event LegacyImportArmed(
        address indexed handoff,
        uint256 expectedEth,
        uint256 expiry,
        uint64 weightVersion,
        bytes32 manifest
    );
    /// @notice Exact legacy ETH entered as 100% protocol capital without the fresh-reward haircut.
    /// @param ethAmount Imported ETH wei.
    /// @param rethEth ETH wei assigned to pending rETH protocol investment.
    /// @param ysyBoldEth ETH wei assigned to pending ysyBOLD protocol investment.
    event LegacyPrincipalImported(uint256 ethAmount, uint256 rethEth, uint256 ysyBoldEth);
    /// @notice Safe explicitly assigned previously unclassified ETH.
    /// @param purpose Zero direct rewards, one rETH protocol investment, two ysyBOLD protocol investment.
    /// @param amount Newly assigned ETH wei, never already assigned cash.
    event EthSurplusRecognized(uint8 indexed purpose, uint256 amount);
    /// @notice Safe retired execution and exported only classified manager-owned buffers.
    /// @param manifest Public reconciliation commitment for this export instance.
    /// @param ethAmount Reconciled assigned ETH wei exported to treasury.
    /// @param boldAmount Classified BOLD base units exported.
    /// @param sBoldAmount Classified sBOLD share base units exported.
    /// @param rethTokens Classified rETH carry base units exported, never vault principal.
    /// @param ysyTokens Classified ysyBOLD carry base units exported, never vault principal.
    /// @param accountingHash Commitment to pre-export purpose/bucket inventory totals.
    event BuffersRecovered(
        bytes32 indexed manifest,
        uint256 ethAmount,
        uint256 boldAmount,
        uint256 sBoldAmount,
        uint256 rethTokens,
        uint256 ysyTokens,
        bytes32 accountingHash
    );
    /// @notice Accidental noncore tokens were transferred only to fixed treasury.
    /// @param token ERC20 identity outside all protected integration assets.
    /// @param amount Transferred native token base units.
    event NoncoreRescued(address indexed token, uint256 amount);

    /// @notice Initialize atomically through ERC1967Proxy; implementations are locked.
    /// @param config Exact reviewed identity set; production preflight also verifies Safe policy and code.
    function initialize(Initialization calldata config) external;
    /// @notice Bind the pair once, checking reciprocal identities while intake remains disabled.
    /// @param rethVault Fixed rETH-native vault proxy with ETH-wei basis.
    /// @param ysyBoldVault Fixed ysyBOLD-native vault proxy with yBOLD basis.
    function bindVaults(address rethVault, address ysyBoldVault) external;
    /// @notice Accept only fresh rewards sent by the fixed pool; no venue calls occur here.
    /// @dev msg.value is positive ETH wei; half goes to direct rewards and only the invested half follows weights.
    function depositFunds() external payable;
    /// @notice Safe changes only allocation of future receipts, never assigned pending capital.
    /// @param rethBps rETH portion of future invested capital, in basis points.
    /// @param ysyBoldBps Complementary ysyBOLD basis points; sum must equal 10,000.
    function setFutureInvestmentWeights(uint16 rethBps, uint16 ysyBoldBps) external;
    /// @notice Safe separately enables/disables pool intake after bootstrap checks.
    /// @param enabled Requested intake state, which cannot override terminal recovery.
    function setIntakeEnabled(bool enabled) external;
    /// @notice Safe configures bounded execution while execution is disabled.
    /// @param executor Verified typed executor, reciprocally bound to this manager and treasury.
    /// @param maxEth Positive ETH-wei operation cap.
    /// @param maxReth Positive rETH-base-unit carry conversion cap.
    /// @param maxYsy Positive ysyBOLD-base-unit carry conversion cap.
    function configureExecution(address executor, uint256 maxEth, uint256 maxReth, uint256 maxYsy) external;
    /// @notice Safe explicitly activates reviewed, nonzero execution configuration.
    /// @param enabled Requested execution state; recovered managers require separately reviewed restoration.
    function setExecutionEnabled(bool enabled) external;
    /// @notice Safe grants/revokes only bounded routine maintenance.
    /// @param operator Nonzero backend/routine address, distinct from fixed treasury.
    /// @param enabled Grant or revoke bounded maintenance.
    function setOperator(address operator, bool enabled) external;
    /// @notice Spend only the selected leg's assigned ETH and credit actual protocol backing.
    /// @param leg Zero rETH or one ysyBOLD.
    /// @param ethAmount ETH wei debited only from that leg's pending assignment.
    /// @param minTokens Minimum actual acquired native-token quantity, alongside executor-enforced floors.
    /// @param minBasis Minimum recognized ETH-wei/yBOLD-unit credit accepted from the leaf.
    /// @param deadline Last acceptable execution timestamp, additionally bounded by the executor.
    function deployProtocolPrincipal(
        uint8 leg,
        uint256 ethAmount,
        uint256 minTokens,
        uint256 minBasis,
        uint256 deadline
    ) external;
    /// @notice Convert only the immediate-reward ETH bucket into classified BOLD.
    /// @param amount Positive ETH wei within assigned direct rewards and configured cap.
    /// @param minBold Minimum BOLD base units received, alongside executor-enforced independent floors.
    /// @param deadline Last acceptable execution timestamp.
    function convertEthRewards(uint256 amount, uint256 minBold, uint256 deadline) external;
    /// @notice Convert only explicitly collected carry into classified BOLD, donating 100% of yield.
    /// @param leg Zero rETH or one ysyBOLD.
    /// @param bucket Original supporter zero or protocol one carry source.
    /// @param amount Source-native token quantity within that classified bucket and operation cap.
    /// @param minBold Minimum actual BOLD base units received.
    /// @param deadline Last acceptable execution timestamp.
    function convertHarvest(uint8 leg, uint8 bucket, uint256 amount, uint256 minBold, uint256 deadline) external;
    /// @notice Convert classified BOLD to actual sBOLD shares, without principal access.
    /// @param amount Positive BOLD base units within classified pending inventory.
    /// @param minShares Minimum actual sBOLD share base units received.
    /// @param deadline Last acceptable execution timestamp.
    function convertBoldToSBold(uint256 amount, uint256 minShares, uint256 deadline) external;
    /// @notice Top up the fixed existing pybSeba once using classified sBOLD only.
    /// @param amount Positive sBOLD base units within classified pending inventory.
    function donateSBold(uint256 amount) external;
    /// @notice Authenticate a configured vault's atomic native-token yield transfer.
    /// @param bucket Source supporter zero or protocol one; leg is derived from caller, never trusted calldata.
    /// @param amount Exact native tokens already transferred by the authenticated vault.
    /// @dev Available during pauses/terminal recovery so native claims/finalization do not depend on reward routing.
    function onYieldReceived(uint8 bucket, uint256 amount) external;
    /// @notice Arm one exact, expiring import independently of disabled ordinary intake.
    /// @param handoff Reviewed immutable one-shot source adapter.
    /// @param expectedEth Exact authorized ETH wei, distinct from legacy native principal units.
    /// @param expiry Latest allowed import timestamp.
    /// @param manifest Public exact migration approval/reconciliation commitment.
    /// @dev An aborted/expired arm requires a fresh disabled candidate or reviewed upgrade; it cannot be rearmed.
    function armLegacyImport(address handoff, uint256 expectedEth, uint256 expiry, bytes32 manifest) external;
    /// @notice The fixed handoff imports 100% as protocol capital exactly once.
    /// @dev msg.value equals armed ETH wei; ordinary pool intake may remain disabled during reviewed bootstrap.
    function importLegacyPrincipal() external payable;
    /// @notice Explicitly classify forced/unassigned ETH, never already assigned capital.
    /// @param purpose Zero direct rewards, one rETH protocol capital, two ysyBOLD protocol capital.
    /// @param amount Positive ETH wei no greater than actual unassigned surplus.
    function recognizeEthSurplus(uint8 purpose, uint256 amount) external;
    /// @notice Permanently freeze intake/execution and export only this manager's reconciled buffers.
    /// @param manifest Nonzero public purpose/bucket reconciliation commitment for this export.
    /// @dev Later authenticated leaf carry can be exported separately; no vault positions or principal are closed.
    function recoverBuffers(bytes32 manifest) external;
    /// @notice Rescue accidental noncore tokens only to the fixed treasury.
    /// @param token ERC20 outside protected investment, basis and conversion-token identities.
    /// @param amount Positive native token base units sent only to treasury.
    function rescueToken(address token, uint256 amount) external;
}
