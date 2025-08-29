// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*───────────────────────────── OpenZeppelin ───────────────────────────*/
import { AccessControl }   from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 }          from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 }           from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/*─────────────────────────────── Interfaces ───────────────────────────*/
import { IEthToBoldRouter } from "src/interfaces/IEthToBoldRouter.sol";
import { ISBOLD }           from "src/vendor/liquity/ISBOLD.sol";
import { IPYBSeba }       from "src/interfaces/IPYBSeba.sol";
import { IYieldVault }      from "src/interfaces/IYieldVault.sol";
import { IYieldManager }    from "src/interfaces/IYieldManager.sol";

/**
 * @title YieldManager
 * @notice Handles BoostPool funding, user deposits (time-locked), ETH→BOLD→sBOLD
 *         conversion, strategy-yield routing, and vault migration.
 */
contract YieldManager is AccessControl, ReentrancyGuard, IYieldManager {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYieldManager
    uint32 public constant USER_LOCK_SECS = 30 days;

    /*//////////////////////////////////////////////////////////////
                             CONFIGURABLES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYieldManager
    uint16 public ROUTER_SLIPPAGE_BPS = 50;     // 0.50 %
    /// @inheritdoc IYieldManager
    uint16 public FEE_BPS = 100;     // 1 %
    /// @inheritdoc IYieldManager
    uint32 public ROUTER_VALIDITY_SECS = 15 minutes;

    /*//////////////////////////////////////////////////////////////
                               ROLES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYieldManager
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @inheritdoc IYieldManager
    bytes32 public constant AUTOMATOR_ROLE = keccak256("AUTOMATOR_ROLE");

    /*//////////////////////////////////////////////////////////////
                       IMMUTABLE EXTERNAL REFERENCES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYieldManager
    address public immutable boostPool;
    /// @inheritdoc IYieldManager
    IEthToBoldRouter public immutable router;
    /// @inheritdoc IYieldManager
    IERC20 public immutable BOLD;
    /// @inheritdoc IYieldManager
    ISBOLD public immutable sBOLD;
    /// @inheritdoc IYieldManager
    IPYBSeba public immutable sebaVault;

    /*//////////////////////////////////////////////////////////////
                             STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// Router / conversion state
    /// @inheritdoc IYieldManager
    bytes32 public activeRouterUid;
    /// @inheritdoc IYieldManager
    bool public yieldFlowActive;
    /// @inheritdoc IYieldManager
    uint256 public pendingBoldConversion;
    /// @inheritdoc IYieldManager
    uint256 public lastConversionStartTimestamp;

    /// Principal tracking (protocol owned)
    /// @inheritdoc IYieldManager
    uint256 public principalValue;

    /// Strategy vault presently in use
    /// @inheritdoc IYieldManager
    IYieldVault public yieldVault;

    /// User deposits
    uint256 public override depositId;
    mapping(uint256 => Deposit) public override deposits;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the YieldManager.
     */
    constructor(
        address admin,
        address automator,
        address _boostPool,
        address _router,
        address _bold,
        address _sbold,
        address _sebaVault,
        address _yieldVault
    ) {
        if (
            admin      == address(0) || automator == address(0) ||
            _boostPool == address(0) || _router   == address(0) ||
            _bold      == address(0) || _sbold    == address(0) ||
            _sebaVault == address(0) || _yieldVault == address(0)
        ) revert InvalidAddress();

        _grantRole(ADMIN_ROLE, admin);
        _grantRole(AUTOMATOR_ROLE, automator);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(AUTOMATOR_ROLE, ADMIN_ROLE);

        boostPool = _boostPool;
        router     = IEthToBoldRouter(_router);
        BOLD       = IERC20(_bold);
        sBOLD      = ISBOLD(_sbold);
        sebaVault  = IPYBSeba(_sebaVault);
        yieldVault = IYieldVault(_yieldVault);
    }

    /*//////////////////////////////////////////////////////////////
                               RECEIVE
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                        FUNDING (BoostPool / Users)
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYieldManager
    function depositFunds() external payable override nonReentrant {
        if (msg.value == 0) revert EmptyDeposit();
        uint256 depositValue;

        /* ---------- 1️⃣  BoostPool deposit: 50 / 50 split ---------- */
        if (msg.sender == boostPool) {
            uint256 half  = msg.value / 2;
            uint256 other = msg.value - half;

            pendingBoldConversion += half;
            depositValue   = yieldVault.deposit{ value: other }();
            principalValue        += depositValue;

            emit DepositReceived(msg.sender, depositValue);
            return;
        }

        /* ---------- 2️⃣  External user deposit (locked) ------------ */
        depositValue = yieldVault.deposit{ value: msg.value }();

        unchecked { ++depositId; }
        deposits[depositId] = Deposit({
            depositor: msg.sender,
            vaultAtDeposit: yieldVault,
            amount: depositValue,
            unlockTime: uint32(block.timestamp + USER_LOCK_SECS)
        });

        emit DepositReceived(msg.sender, depositValue);
        emit FundsDeposited(depositId, msg.sender, msg.value);
    }

    /*//////////////////////////////////////////////////////////////
                      USER PRINCIPAL RETRIEVAL
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYieldManager
    function retrieveFunds(uint256 id) external override nonReentrant {
        Deposit memory d = deposits[id];
        if (d.amount == 0)               revert NonExistingDeposit(id);
        if (d.depositor != msg.sender)   revert InvalidDepositor(msg.sender);
        if (block.timestamp < d.unlockTime)
            revert DepositStillLocked(block.timestamp, d.unlockTime);

        delete deposits[id];

        uint256 pre = address(this).balance;
        d.vaultAtDeposit.retrievePrincipal(d.amount);
        uint256 post = address(this).balance;
        uint256 funds = post - pre;

        (bool ok, ) = msg.sender.call{ value: funds }("");
        if (!ok) revert TransferFailed();

        emit FundsRetrieved(id, msg.sender, funds);
    }

    /*//////////////////////////////////////////////////////////////
                      ETH→BOLD→sBOLD CONVERSION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYieldManager
    function runBoldConversion() external override {
        /* 1️⃣  Cancel expired router intent & reclaim ETH */
        if (block.timestamp > lastConversionStartTimestamp + ROUTER_VALIDITY_SECS) {
            if (_hasOpenRouterIntent()) {
                uint256 pre = address(this).balance;
                _finalizeRouterIntent();
                uint256 post = address(this).balance;
                unchecked { pendingBoldConversion += post - pre; }
            }

            /* 2️⃣  Finalise any BOLD→sBOLD conversion */
            _runSBoldConversion();

            /* 3️⃣  Start a new ETH→BOLD intent if funds pending */
            if (pendingBoldConversion > 0) {
                uint256 ethIn = pendingBoldConversion;
                bytes32 uid = router.swapExactEthForBold{ value: ethIn }(
                FEE_BPS,
                    ROUTER_SLIPPAGE_BPS,
                    ROUTER_VALIDITY_SECS
                );
                activeRouterUid = uid;
                pendingBoldConversion = 0;
                emit BoldConversionStarted(uid, ethIn);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            YIELD MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYieldManager
    function distributeYield() external override onlyRole(AUTOMATOR_ROLE) {
        uint256 pre = address(this).balance;
        yieldVault.claimYield();
        uint256 ethAmount = address(this).balance - pre;

        if (ethAmount > 0) {
            if (!yieldFlowActive) {
                yieldVault.deposit{ value: ethAmount }();
                emit YieldDistributed(ethAmount, false);
                return;
            }
            pendingBoldConversion += ethAmount;
        }
        emit YieldDistributed(ethAmount, true);
    }

    /// @inheritdoc IYieldManager
    function activateYieldFlow() external override onlyRole(ADMIN_ROLE) {
        if (yieldFlowActive) revert YieldFlowAlreadyActivated();
        yieldFlowActive = true;
        emit YieldFlowActivated();
    }

    /*//////////////////////////////////////////////////////////////
                            VAULT MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYieldManager
    function setYieldVault(address _yieldVault) external override onlyRole(ADMIN_ROLE) {
        if (principalValue > 0) {
            yieldVault.retrievePrincipal(principalValue);
            principalValue = 0;
            emit PrincipalRetrieved();
        }
        yieldVault = IYieldVault(_yieldVault);
        emit NewYieldVaultSet(_yieldVault);
    }

    /// @inheritdoc IYieldManager
    function retrievePrincipalFromYieldVault() external override onlyRole(ADMIN_ROLE) {
        if (principalValue == 0) revert NoPrincipalDeployed();
        yieldVault.retrievePrincipal(principalValue);
        principalValue = 0;
        emit PrincipalRetrieved();
    }

    /// @inheritdoc IYieldManager
    function depositPrincipalIntoYieldVault() external override onlyRole(ADMIN_ROLE) {
        uint256 principal = address(this).balance - pendingBoldConversion;
        principalValue += yieldVault.deposit{ value: principal }();
        emit PrincipalDeposited(principal);
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN CONFIG SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IYieldManager
    function setRouterSlippageBps(uint16 _bps) external override onlyRole(ADMIN_ROLE) {
        require(_bps <= 10_000, "slippage bps out of range");
        uint16 prev = ROUTER_SLIPPAGE_BPS;
        ROUTER_SLIPPAGE_BPS = _bps;
        emit RouterSlippageBpsSet(prev, _bps);
    }

    /// @inheritdoc IYieldManager
    function setRouterValiditySecs(uint32 _secs) external override onlyRole(ADMIN_ROLE) {
        require(_secs > 0, "validity must be > 0");
        uint32 prev = ROUTER_VALIDITY_SECS;
        ROUTER_VALIDITY_SECS = _secs;
        emit RouterValiditySecsSet(prev, _secs);
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNALS
    //////////////////////////////////////////////////////////////*/

    function _runSBoldConversion() internal {
        uint256 boldBal = BOLD.balanceOf(address(this));
        if (boldBal > 0) {
            BOLD.approve(address(sBOLD), boldBal);
            uint256 sOut = sBOLD.deposit(boldBal, address(this));

            ERC20(address(sBOLD)).approve(address(sebaVault), sOut);
            sebaVault.topup(sOut);

            emit BoldConversionFinalised(boldBal, sOut);
        }
    }

    function _finalizeRouterIntent() internal {
        if (activeRouterUid.length == 0) revert NoActiveRouterIntent();
        router.finalizeIntent();
        delete activeRouterUid;
    }

    function _hasOpenRouterIntent() internal view returns (bool) {
        return (activeRouterUid.length > 0);
    }
}
