// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Native supporter principal and recovery interface
/// @author Seba contributors
/// @notice Amounts use asset base units; basis uses ETH wei (rETH) or yBOLD base units (ysyBOLD).
interface IV2SupporterVault {
    enum RecoveryState {
        Normal,
        Custody,
        Settlement,
        Settled
    }

    struct Position {
        address owner;
        uint256 basis;
        uint256 unlockAt;
        bool closed;
    }
    struct Bucket {
        uint256 basis;
        uint256 tokens;
        uint256 enteredBasis;
        uint256 removedBasis;
        uint256 principalTokensPaid;
        uint256 harvestedTokens;
        uint256 repairTokens;
        uint256 realizedLossBasis;
    }
    struct RecoveryBucket {
        Bucket snapshot;
        uint256 exportedTokens;
        uint256 returnedTokens;
        uint256 repairTokens;
        uint256 budget;
        uint256 paidTokens;
        uint256 closedBasis;
        uint256 refundableRepairTokens;
    }

    error Unauthorized();
    error InvalidConfiguration();
    error InvalidAmount();
    error InvalidBucket();
    error WrongState();
    error Expired();
    error EntriesDisabled();
    error HarvestDisabled();
    error StaleReport();
    error InvalidRate();
    error Deficit();
    error CustodyShortfall();
    error UnexpectedTokenDelta();
    error Slippage();
    error PositionLocked();
    error ClosedPosition();
    error UnfundedSettlement();
    error InvalidBudget();
    error ValuationAvailable();
    error OutstandingLiabilities();

    /// @notice A native-token supporter claim was created.
    /// @param id Local position ID, namespaced by chain and proxy.
    /// @param owner Fixed position owner.
    /// @param tokens Exact deposited native-token base units.
    /// @param basis Recognized native-value principal, in ETH wei or yBOLD units.
    /// @param unlockAt Original withdrawal-unlock timestamp.
    event PositionOpened(uint256 indexed id, address indexed owner, uint256 tokens, uint256 basis, uint256 unlockAt);
    /// @notice A supporter claim was permanently closed through the contract.
    /// @param id Local position ID.
    /// @param owner Recipient and original position owner.
    /// @param basis Native-value liability removed, regardless of realized loss.
    /// @param tokens Exact native-token payout, possibly zero only in recovery.
    /// @param recovery Whether the fixed recovery budget governed payout.
    event PositionClosed(uint256 indexed id, address indexed owner, uint256 basis, uint256 tokens, bool recovery);
    /// @notice Actual acquired native tokens credited segregated protocol capital.
    /// @param tokens Exact acquired native-token quantity.
    /// @param basis Recognized native-value credit, not gross ETH acquisition cost.
    event ProtocolDeposited(uint256 tokens, uint256 basis);
    /// @notice Safe closed protocol principal to the fixed treasury.
    /// @param basis Native-value liability removed.
    /// @param tokens Exact native tokens paid.
    /// @param recovery Whether the fixed recovery budget governed payout.
    event ProtocolWithdrawn(uint256 basis, uint256 tokens, bool recovery);
    /// @notice A normal withdrawal realized impairment or floor-rounding loss.
    /// @param bucket Supporter zero or protocol one.
    /// @param removedBasis Native-value liability closed.
    /// @param returnedBasis Canonical recognized value of returned tokens.
    /// @param lossBasis Difference from removed basis, never deducted again from remaining claims.
    event RealizedLoss(uint8 indexed bucket, uint256 removedBasis, uint256 returnedBasis, uint256 lossBasis);
    /// @notice Carry was transferred and atomically classified by the fixed manager.
    /// @param bucket Source capital bucket.
    /// @param tokens Exact native tokens collected, not completed validator donation.
    event YieldCollected(uint8 indexed bucket, uint256 tokens);
    /// @notice A donor added ordinary backing without minting principal.
    /// @param bucket Repaired bucket only.
    /// @param donor Address providing exact native tokens.
    /// @param tokens Exact received quantity.
    event Repaired(uint8 indexed bucket, address indexed donor, uint256 tokens);
    /// @notice Safe explicitly assigned previously quarantined native-token surplus.
    /// @param bucket Receiving bucket.
    /// @param tokens Exact classified amount already in custody.
    /// @param repair Whether assignment was explicit loss repair rather than healthy donated carry.
    event SurplusRecognized(uint8 indexed bucket, uint256 tokens, bool repair);
    /// @notice Safe changed entry configuration only.
    /// @param minimumBasis Minimum native-value credit per entry.
    /// @param enabled New entry-enable flag.
    event EntryConfigured(uint256 minimumBasis, bool enabled);
    /// @notice Safe changed bounded carry-collection configuration.
    /// @param maximumTokens Maximum native tokens collectible per call.
    /// @param enabled New collection-enable flag.
    event HarvestConfigured(uint256 maximumTokens, bool enabled);
    /// @notice Safe granted or revoked bounded collection permission.
    /// @param operator Routine operator address.
    /// @param enabled Whether that address may collect within configured bounds.
    event OperatorSet(address indexed operator, bool enabled);
    /// @notice Ordinary operation froze and native custody was exported to the fixed Safe.
    /// @param instanceId Immutable recovery identity binding chain, proxy and snapshot.
    /// @param manifest Initial public custody-evidence commitment.
    /// @param positionBoundary Exclusive upper supporter-ID boundary.
    /// @param surplus Native tokens not attributed to either bucket.
    /// @param actualExport Exact aggregate native tokens transferred to Safe.
    /// @param shortage Whether physical custody was below total pre-export accounted tokens.
    event RecoveryStarted(
        bytes32 indexed instanceId,
        bytes32 indexed manifest,
        uint256 positionBoundary,
        uint256 surplus,
        uint256 actualExport,
        bool shortage
    );
    /// @notice Frozen principal/custody attribution for one recovery bucket.
    /// @param instanceId Recovery identity shared with the aggregate export.
    /// @param bucket Supporter zero or protocol one.
    /// @param basis Outstanding native-value liability.
    /// @param accountedTokens Expected pre-export native-token custody.
    /// @param exportedTokens Actual native tokens attributed after proportional shortage reconciliation.
    /// @param valuationAvailable Whether the canonical value query succeeded.
    /// @param recognizedValue Recognized value at snapshot, meaningful only when valuation is available.
    event RecoveryBucketSnapshot(
        bytes32 indexed instanceId,
        uint8 indexed bucket,
        uint256 basis,
        uint256 accountedTokens,
        uint256 exportedTokens,
        bool valuationAvailable,
        uint256 recognizedValue
    );
    /// @notice Explicit returned backing or irrevocable repair funding was authenticated.
    /// @param bucket Receiving bucket, never a cross-bucket subsidy.
    /// @param contributor Address supplying exact native tokens.
    /// @param tokens Exact received funding quantity.
    /// @param repair True for additional irrevocable repair; false for returning exported custody.
    event RecoveryFunded(uint8 indexed bucket, address indexed contributor, uint256 tokens, bool repair);
    /// @notice Safe provided separately tagged potentially refundable additional backing.
    /// @param bucket Receiving bucket after all its original exported backing was returned.
    /// @param contributor Fixed treasury Safe funding this refundable subset.
    /// @param tokens Exact received amount; also part of total additional repair backing.
    event RecoveryRefundableFunded(uint8 indexed bucket, address indexed contributor, uint256 tokens);
    /// @notice Fixed, fully funded token budgets activated exactly once.
    /// @param instanceId Immutable custody recovery identity.
    /// @param manifest Final classification/budget evidence commitment, distinct from initial evidence.
    /// @param exceptional Whether unavailable valuation required explicit trusted Safe classification.
    /// @param supporterBudget Fixed supporter token numerator against snapshot supporter basis.
    /// @param protocolBudget Fixed protocol token numerator against snapshot protocol basis.
    event SettlementActivated(
        bytes32 indexed instanceId,
        bytes32 indexed manifest,
        bool exceptional,
        uint256 supporterBudget,
        uint256 protocolBudget
    );
    /// @notice An original liability was closed against the fixed recovery token rate.
    /// @param bucket Paying escrow bucket.
    /// @param id Supporter ID, or reserved zero for protocol aggregate/partial claims.
    /// @param basis Native-value basis closed exactly once.
    /// @param tokens Same-token fixed-rate payout, including explicit zero-budget claims.
    event RecoveryClaimed(uint8 indexed bucket, uint256 indexed id, uint256 basis, uint256 tokens);
    /// @notice All liabilities closed; remaining carry/dust was classified and unused refundable funding returned.
    /// @param instanceId Completed recovery identity.
    /// @param supporterYield Native tokens donated from supporter residuals and unassigned surplus.
    /// @param protocolYield Native tokens donated from protocol residuals.
    /// @param repairRefund Unused explicitly refundable funding returned only to treasury.
    event RecoveryFinalized(
        bytes32 indexed instanceId,
        uint256 supporterYield,
        uint256 protocolYield,
        uint256 repairRefund
    );
    /// @notice Accidental noncore tokens were sent to fixed treasury, never an arbitrary receiver.
    /// @param token ERC20 other than the fixed protected native custody token.
    /// @param amount Transferred token base units.
    event NoncoreRescued(address indexed token, uint256 amount);

    /// @notice Read the fixed deposit and payout token.
    /// @return Fixed native deposit/withdrawal ERC20.
    function asset() external view returns (address);
    /// @notice Read the principal-basis identity, distinct from the payout token.
    /// @return ETH sentinel address(0) or the fixed yBOLD token.
    function basisAsset() external view returns (address);
    /// @notice Read the sole protocol depositor and fixed yield destination.
    /// @return Fixed protocol/yield coordinator proxy.
    function manager() external view returns (address);
    /// @notice Read the fixed governance, upgrade and recovery authority.
    /// @return Fixed Safe authority and recovery recipient.
    function treasury() external view returns (address);
    /// @notice Read an original supporter record without changing its lifecycle.
    /// @return Record, retaining its owner and original lock after closure.
    /// @param id Local vault position ID; external identity also includes chain and proxy address.
    function position(uint256 id) external view returns (Position memory);
    /// @notice Read one segregated live accounting ledger.
    /// @return Live native-basis principal and token accounting.
    /// @param which Zero for supporter capital, one for protocol capital.
    function bucket(uint8 which) external view returns (Bucket memory);
    /// @notice Read frozen snapshot and authenticated recovery reconciliation.
    /// @return Frozen recovery basis, custody, funding and payment accounting.
    /// @param which Zero for supporter capital, one for protocol capital.
    function recoveryBucket(uint8 which) external view returns (RecoveryBucket memory);
    /// @notice Read one coherent canonical conversion snapshot, not a DEX or USD price.
    /// @return numerator Canonical recognized backing; zero means economic impairment.
    /// @return denominator Canonical effective token supply, with protocol zero-supply convention applied.
    function rateSnapshot() external view returns (uint256 numerator, uint256 denominator);
    /// @notice Preview recognized backing, deficit and protected/donatable native tokens.
    /// @return value Current recognized native value.
    /// @return deficit Outstanding basis less recognized value, floored at zero.
    /// @return reserve Protected token quantity, rounded up while healthy.
    /// @return carry Harvestable tokens above the reserve.
    /// @param which Zero for supporter capital, one for protocol capital.
    function accounting(
        uint8 which
    ) external view returns (uint256 value, uint256 deficit, uint256 reserve, uint256 carry);
    /// @notice Preview payout without waiving execution-time ownership, lock or custody checks.
    /// @return Native tokens payable for this position under current normal or fixed recovery rules.
    /// @param id Local position ID; this preview does not waive its owner, lock, deadline or custody checks.
    function previewWithdraw(uint256 id) external view returns (uint256);
    /// @notice Pull exact tokens and create a caller-owned position locked for thirty days.
    /// @param tokens Fixed native-token quantity to pull from caller.
    /// @param minBasis Minimum recognized native-value basis acceptable to caller.
    /// @param deadline Last acceptable execution timestamp.
    /// @return id Newly created local position ID.
    /// @return basis Actual floor-rounded native-value principal credited at entry.
    function deposit(uint256 tokens, uint256 minBasis, uint256 deadline) external returns (uint256 id, uint256 basis);
    /// @notice Close the caller's unlocked position and pay its native-token principal.
    /// @param id Caller-owned local position ID.
    /// @param minTokensOut Minimum acceptable same-token payout.
    /// @param deadline Last acceptable execution timestamp.
    /// @return tokens Same-token amount actually paid; zero only under explicit fixed recovery settlement.
    function withdraw(uint256 id, uint256 minTokensOut, uint256 deadline) external returns (uint256 tokens);
    /// @notice Manager-only exact-token credit to its segregated protocol bucket.
    /// @param tokens Actual acquired native tokens, not gross ETH spent on acquisition.
    /// @param minBasis Minimum acceptable recognized native-value credit.
    /// @param deadline Last acceptable execution timestamp.
    /// @return basis Recognized native principal credited only to the protocol bucket.
    function depositProtocol(uint256 tokens, uint256 minBasis, uint256 deadline) external returns (uint256 basis);
    /// @notice Safe-only protocol principal withdrawal to the fixed treasury.
    /// @param basis Native-value principal basis to close, up to the remaining protocol basis.
    /// @param minTokensOut Minimum acceptable same-token payout.
    /// @param deadline Last acceptable execution timestamp.
    /// @return tokens Exact native tokens paid to the fixed treasury.
    function withdrawProtocol(uint256 basis, uint256 minTokensOut, uint256 deadline) external returns (uint256 tokens);
    /// @notice Move only recognized carry to the fixed manager, atomically classifying its receipt.
    /// @param which Bucket whose own carry is collected; no cross-bucket netting.
    /// @param maxTokens Caller maximum within the Safe-configured operation cap.
    /// @return tokens Actual collected quantity; zero means no recognized carry.
    function collectYield(uint8 which, uint256 maxTokens) external returns (uint256 tokens);
    /// @notice Donate exact tokens to repair one bucket, without creating principal.
    /// @param which Bucket receiving the irrevocable repair.
    /// @param tokens Exact native tokens pulled from donor.
    function repair(uint8 which, uint256 tokens) external;
    /// @notice Safe-only explicit classification of previously unassigned tokens.
    /// @param which Bucket receiving the already held tokens.
    /// @param tokens Positive quantity no greater than unassigned surplus.
    /// @param isRepair Explicit repair classification; false cannot silently repair an impaired bucket.
    function recognizeSurplus(uint8 which, uint256 tokens, bool isRepair) external;
    /// @notice Freeze ordinary operations and export accounted custody to the fixed Safe.
    /// @param manifest Nonzero initial custody evidence commitment, immutable after export.
    function beginRecovery(bytes32 manifest) external;
    /// @notice Return previously exported backing; this is not additional repair backing.
    /// @param which Original bucket of the returned custody.
    /// @param tokens Positive exact quantity within that bucket's exported-returned amount.
    function fundRecovery(uint8 which, uint256 tokens) external;
    /// @notice Irrevocably donate extra recovery backing; unused donation is never a treasury refund.
    /// @param which Bucket receiving extra backing, without any new principal claim.
    /// @param tokens Exact donated native tokens.
    function repairRecovery(uint8 which, uint256 tokens) external;
    /// @notice Safe-only additional backing explicitly eligible for excess refund, after original backing is returned.
    /// @param which Bucket receiving separately authenticated additional backing.
    /// @param tokens Exact Safe-funded native tokens; any unused refundable subset returns only to treasury.
    function fundRefundableRecovery(uint8 which, uint256 tokens) external;
    /// @notice Safe-only fixed, fully funded budgets validated using available canonical accounting.
    /// @param budgets Immutable supporter/protocol token budgets, in that order; each can explicitly be zero.
    /// @param manifest Nonzero final reconciliation commitment, distinct from the initial evidence commitment.
    function activateSettlement(uint256[2] calldata budgets, bytes32 manifest) external;
    /// @notice Safe-only published manual classification, solely when canonical valuation is unavailable.
    /// @param budgets Independently reconciled, fully funded same-token budgets; no cross-bucket subsidy.
    /// @param manifest Public exceptional-mode classification commitment including upside/donation/loss disclosure.
    function activateExceptionalSettlement(uint256[2] calldata budgets, bytes32 manifest) external;
    /// @notice After all claims close, classify residual carry and refund unused voluntary repair funding.
    function finalizeRecovery() external;
}

/// @title Authenticated native vault yield receipt interface
/// @author Seba contributors
/// @notice Called atomically after a vault transfers its fixed token to its fixed manager.
interface IV2VaultYieldReceiver {
    /// @notice Authenticate msg.sender as a configured leaf and classify precisely the received amount.
    /// @param bucket Zero for supporter carry and one for protocol carry.
    /// @param tokens Exact native tokens already transferred by that fixed leaf.
    function onYieldReceived(uint8 bucket, uint256 tokens) external;
}
