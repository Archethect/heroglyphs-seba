// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IEthToBoldRouter } from "src/interfaces/IEthToBoldRouter.sol";
import { ISBOLD } from "src/vendor/liquity/ISBOLD.sol";
import { IPYBSeba } from "src/interfaces/IPYBSeba.sol";
import { IYieldVault } from "src/interfaces/IYieldVault.sol";

/**
 * @title IYieldManager
 * @notice Interface for the Seba Yield-Manager that
 *         - handles BoostPool funding (50 / 50 split),
 *         - accepts time-locked user deposits,
 *         - manages ETH→BOLD→sBOLD conversion and SebaVault top-ups,
 *         - claims and routes strategy yield,
 *         - lets admins migrate or pull principal from the active vault.
 */
interface IYieldManager {
    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Configuration for one user deposit that is locked for
    ///         `USER_LOCK_SECS` seconds after the block timestamp.
    /// @param depositor        The user who supplied the ETH.
    /// @param vaultAtDeposit   Strategy vault that currently holds the funds.
    /// @param amount           Principal amount in underlying (ETH value, wei).
    /// @param unlockTime       Timestamp (UTC-seconds) after which withdrawal
    ///                         via {retrieveFunds} is allowed.
    struct Deposit {
        address depositor;
        IYieldVault vaultAtDeposit;
        uint256 amount;
        uint32 unlockTime;
    }

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// Thrown when an address argument is zero.
    error InvalidAddress();

    /// Thrown when `msg.value == 0` in {depositFunds}.
    error EmptyDeposit();

    /// Thrown when trying to cancel a CowSwap order but no UID is stored.
    error NoActiveRouterIntent();

    /// Thrown if {activateYieldFlow} is called more than once.
    error YieldFlowAlreadyActivated();

    /// Thrown when a referenced deposit‐ID does not exist.
    error NonExistingDeposit(uint256 id);

    /// Thrown when someone other than the original depositor calls {retrieveFunds}.
    error InvalidDepositor(address depositor);

    /// Thrown when a user tries to withdraw before `unlockTime`.
    error DepositStillLocked(uint256 now_, uint32 unlockTime);

    /// Thrown when an ETH transfer to a user fails.
    error TransferFailed();

    /// Thrown when admin tries to pull protocol principal but none is deployed.
    error NoPrincipalDeployed();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// Emitted after any ETH deposit is processed
    /// (BoostPool or external user).
    /// @param from              Sender of the ETH.
    /// @param amountUnderlying  Amount accounted as *underlying* (ETH value)
    ///                          and forwarded to a strategy vault (if any).
    event DepositReceived(address indexed from, uint256 amountUnderlying);

    /// Emitted when a new ETH→BOLD CowSwap order (intent) is started.
    /// @param uid    56-byte unique identifier returned by Eth-flow.
    /// @param ethIn  Exact ETH amount committed to the order.
    event BoldConversionStarted(bytes32 uid, uint256 ethIn);

    /// Emitted when BOLD is converted to sBOLD and staked into SebaVault.
    /// @param boldIn   BOLD tokens consumed.
    /// @param sBoldOut sBOLD tokens minted & deposited.
    event BoldConversionFinalised(uint256 boldIn, uint256 sBoldOut);

    /// Emitted once when admin switches yield routing to SebaVault.
    event YieldFlowActivated();

    /// Emitted every time yield is handled.
    /// @param ethAmount    Yield size in ETH.
    /// @param toSebaVault  True  = routed to SebaVault via conversion.<br>
    ///                     False = auto-compounded in the current vault.
    event YieldDistributed(uint256 ethAmount, bool toSebaVault);

    /// Emitted when slippage tolerance for CowSwap intents is adjusted.
    event RouterSlippageBpsSet(uint16 previous, uint16 current);

    /// Emitted when validity window for CowSwap intents is adjusted.
    event RouterValiditySecsSet(uint32 previous, uint32 current);

    /// Emitted after a successful strategy-vault migration.
    event NewYieldVaultSet(address yieldVault);

    /// Emitted when protocol principal is pulled back to this contract.
    event PrincipalRetrieved();

    /// Emitted when protocol principal is (re)deployed into the active vault.
    event PrincipalDeposited(uint256 principal);

    /// Emitted on new user deposit creation.
    event FundsDeposited(uint256 depositId, address depositor, uint256 amountEth);

    /// Emitted when a user successfully withdraws principal.
    event FundsRetrieved(uint256 depositId, address depositor, uint256 amountEth);

    /*//////////////////////////////////////////////////////////////
                       PUBLIC CONSTANTS & VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Seconds a user deposit remains locked.
    function USER_LOCK_SECS() external view returns (uint32);

    /// @notice CowSwap fee (basis-points, 1 bp = 0.01 %).
    function FEE_BPS() external view returns (uint16);

    /// @notice CowSwap slippage tolerance (basis-points, 1 bp = 0.01 %).
    function ROUTER_SLIPPAGE_BPS() external view returns (uint16);

    /// @notice CowSwap order validity in seconds.
    function ROUTER_VALIDITY_SECS() external view returns (uint32);

    /// Role IDs used by AccessControl.
    function ADMIN_ROLE() external view returns (bytes32);
    function AUTOMATOR_ROLE() external view returns (bytes32);

    /// External contract references
    function router() external view returns (IEthToBoldRouter);
    function BOLD() external view returns (IERC20);
    function sBOLD() external view returns (ISBOLD);
    function sebaVault() external view returns (IPYBSeba);
    function yieldVault() external view returns (IYieldVault);
    function boostPool() external view returns (address);

    /// Conversion & yield state
    function activeRouterUid() external view returns (bytes32);
    function pendingBoldConversion() external view returns (uint256);
    function yieldFlowActive() external view returns (bool);
    function lastConversionStartTimestamp() external view returns (uint256);

    /// Principal deployed on behalf of Seba (ETH value)
    function principalValue() external view returns (uint256);

    /// Incrementing deposit counter
    function depositId() external view returns (uint256);

    /// Mapping accessor for deposits
    function deposits(
        uint256 id
    ) external view returns (address depositor, IYieldVault vaultAtDeposit, uint256 amount, uint32 unlockTime);

    /*//////////////////////////////////////////////////////////////
                                ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit ETH into the manager.
     *         • If `msg.sender == boostPool`: 50 / 50 split — half routed
     *           to CowSwap, half deposited into the strategy vault.
     *         • Else: entire amount deposited & locked under the caller.
     *
     * @dev Emits {DepositReceived}.
     *      Emits {FundsDeposited} for the *user* branch.
     *
     * Reverts {EmptyDeposit}.
     */
    function depositFunds() external payable;

    /**
     * @notice Withdraw the caller’s locked principal once the lock expires.
     * @param id  The deposit ID obtained from {FundsDeposited}.
     *
     * @dev Reverts {NonExistingDeposit}, {InvalidDepositor},
     *      {DepositStillLocked}.
     *      Emits {FundsRetrieved}.
     */
    function retrieveFunds(uint256 id) external;

    /**
     * @notice House-keeping for the ETH→BOLD→sBOLD pipeline:
     *         - Cancel & refund expired CowSwap order (if any),
     *         - Convert any held BOLD into sBOLD & top-up SebaVault,
     *         - Start a new CowSwap order if ETH is pending.
     *
     * @dev Emits {BoldConversionFinalised} and/or {BoldConversionStarted}.
     */
    function runBoldConversion() external;

    /**
     * @notice Claim yield from the active vault.
     *         • If `yieldFlowActive == false`: auto-compound back into vault.
     *         • Else: add ETH to pending conversion for SebaVault top-up.
     *
     * @dev Restricted to role `AUTOMATOR_ROLE`.
     *      Emits {YieldDistributed}.
     */
    function distributeYield() external;

    /**
     * @notice One-time switch that routes *future* yield to SebaVault
     *         via the sBOLD conversion path.
     *
     * @dev Reverts {YieldFlowAlreadyActivated}.
     *      Emits {YieldFlowActivated}.
     *      Only an `ADMIN_ROLE` holder may call.
     */
    function activateYieldFlow() external;

    /* ----------------------------- Admin ops --------------------------- */

    /**
     * @notice Point the manager at a new strategy vault.
     *         Existing principal is pulled first.
     */
    function setYieldVault(address _yieldVault) external;

    /// Retrieve protocol-owned principal from the current vault.
    function retrievePrincipalFromYieldVault() external;

    /// Deposit any idle principal held by this contract into the vault.
    function depositPrincipalIntoYieldVault() external;

    /// Adjust CowSwap slippage tolerance (basis-points).
    function setRouterSlippageBps(uint16 _bps) external;

    /// Adjust CowSwap order validity window (seconds).
    function setRouterValiditySecs(uint32 _secs) external;
}
