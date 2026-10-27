// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { YieldManagerV2 } from "src/v2/YieldManagerV2.sol";
import { IYieldManagerV2 } from "src/interfaces/v2/IYieldManagerV2.sol";
import { IV2Executor } from "src/interfaces/v2/IV2Executor.sol";

contract ManagerSafeMock {
    bool public rejectEth;
    function setRejectEth(bool value) external {
        rejectEth = value;
    }
    receive() external payable {
        require(!rejectEth, "test receiver rejects ETH");
    }
}

contract ManagerTokenMock is ERC20 {
    address public asset;
    bool public brokenBalance;
    uint8 public mode;
    constructor(address underlying) ERC20("TEST ONLY", "TEST") {
        asset = underlying;
    }
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
    function setBrokenBalance(bool value) external {
        brokenBalance = value;
    }
    function setMode(uint8 value) external {
        mode = value;
    }
    function previewDeposit(uint256 amount) external view returns (uint256) {
        return mode == 4 ? 0 : amount;
    }
    function balanceOf(address who) public view override returns (uint256) {
        require(!brokenBalance, "test unavailable token");
        return super.balanceOf(who);
    }
    function deposit(uint256 amount, address receiver) external returns (uint256 shares) {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        if (mode == 1) return 0;
        shares = mode == 3 ? amount - 1 : amount;
        _mint(receiver, shares);
        if (mode == 2) return shares + 1;
    }
}

contract ManagerSinkMock {
    address public asset;
    bool public broken;
    constructor(address token) {
        asset = token;
    }
    function setBroken(bool value) external {
        broken = value;
    }
    function topup(uint256 amount) external {
        require(!broken, "test sink unavailable");
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
    }
}

contract ManagerPoolMock {
    function submit(YieldManagerV2 manager) external payable {
        manager.depositFunds{ value: msg.value }();
    }
}

contract ManagerVaultMock {
    address public asset;
    address public basisAsset;
    address public manager;
    address public treasury;
    uint256 public protocolBasis;
    uint8 public mode;
    constructor(address token, address basis, address coordinator, address safe) {
        asset = token;
        basisAsset = basis;
        manager = coordinator;
        treasury = safe;
    }
    function setMode(uint8 value) external {
        mode = value;
    }
    function depositProtocol(uint256 amount, uint256 minimum, uint256) external returns (uint256) {
        require(msg.sender == manager, "test manager only");
        if (mode == 1) return 0;
        IERC20(asset).transferFrom(msg.sender, address(this), mode == 2 ? amount - 1 : amount);
        require(amount >= minimum, "test min basis");
        protocolBasis += amount;
        return amount;
    }
    function harvest(uint8 bucket, uint256 amount) external {
        ManagerTokenMock(asset).mint(manager, amount);
        YieldManagerV2(payable(manager)).onYieldReceived(bucket, amount);
    }
}

contract ManagerExecutorMock is IV2Executor {
    Config private _config;
    bool public enabled = true;
    uint8 public mode;
    constructor(Config memory c) {
        _config = c;
    }
    function manager() external view returns (address) {
        return _config.manager;
    }
    function treasury() external view returns (address) {
        return _config.treasury;
    }
    function configuration() external view returns (Config memory) {
        return _config;
    }
    function limits() external pure returns (Limits memory result) {
        return result;
    }
    function configureLimits(Limits calldata) external {}
    function setEnabled(bool value) external {
        enabled = value;
    }
    function setMode(uint8 value) external {
        mode = value;
    }
    function investReth(uint256, uint256) external payable returns (uint256) {
        return _eth(_config.reth);
    }
    function investYsyBold(uint256, uint256) external payable returns (uint256) {
        return _eth(_config.ysyBold);
    }
    function convertEthToBold(uint256, uint256) external payable returns (uint256) {
        return _eth(_config.bold);
    }
    function convertRethToBold(uint256 amount, uint256, uint256) external returns (uint256) {
        return _tokens(_config.reth, amount);
    }
    function convertYsyToBold(uint256 amount, uint256, uint256) external returns (uint256) {
        return _tokens(_config.ysyBold, amount);
    }
    function _eth(address token) private returns (uint256) {
        if (mode == 2) return 0;
        ManagerTokenMock(token).mint(msg.sender, msg.value);
        if (mode == 3) {
            (bool ok, ) = msg.sender.call{ value: 1 }("");
            require(ok);
        }
        return mode == 1 ? msg.value + 1 : msg.value;
    }
    function _tokens(address token, uint256 amount) private returns (uint256) {
        IERC20(token).transferFrom(msg.sender, address(this), mode == 4 ? amount - 1 : amount);
        if (mode == 2) return 0;
        ManagerTokenMock(_config.bold).mint(msg.sender, amount);
        return mode == 1 ? amount + 1 : amount;
    }
}

abstract contract ManagerTestBase is Test {
    YieldManagerV2 internal manager;
    ManagerSafeMock internal safe;
    ManagerPoolMock internal pool;
    ManagerTokenMock internal boldToken;
    ManagerTokenMock internal sBoldToken;
    ManagerTokenMock internal rethToken;
    ManagerTokenMock internal ysyToken;
    ManagerTokenMock internal yBoldToken;
    ManagerTokenMock internal wethToken;
    ManagerTokenMock internal usdcToken;
    ManagerSinkMock internal sink;
    ManagerVaultMock internal rVault;
    ManagerVaultMock internal yVault;
    ManagerExecutorMock internal execution;
    address internal operator;

    function setUp() public virtual {
        vm.warp(1_800_000_000);
        safe = new ManagerSafeMock();
        pool = new ManagerPoolMock();
        operator = makeAddr("bounded operator");
        boldToken = new ManagerTokenMock(address(0));
        sBoldToken = new ManagerTokenMock(address(boldToken));
        rethToken = new ManagerTokenMock(address(0));
        yBoldToken = new ManagerTokenMock(address(boldToken));
        ysyToken = new ManagerTokenMock(address(yBoldToken));
        wethToken = new ManagerTokenMock(address(0));
        usdcToken = new ManagerTokenMock(address(0));
        sink = new ManagerSinkMock(address(sBoldToken));
        YieldManagerV2 implementation = YieldManagerV2(payable(deployCode("YieldManagerV2.sol:YieldManagerV2")));
        manager = YieldManagerV2(
            payable(
                address(
                    new ERC1967Proxy(
                        address(implementation),
                        abi.encodeCall(implementation.initialize, (_configuration()))
                    )
                )
            )
        );
        rVault = new ManagerVaultMock(address(rethToken), address(0), address(manager), address(safe));
        yVault = new ManagerVaultMock(address(ysyToken), address(yBoldToken), address(manager), address(safe));
        IV2Executor.Config memory c;
        c.manager = address(manager);
        c.treasury = address(safe);
        c.reth = address(rethToken);
        c.ysyBold = address(ysyToken);
        c.bold = address(boldToken);
        c.yBold = address(yBoldToken);
        c.weth = address(wethToken);
        c.usdc = address(usdcToken);
        execution = new ManagerExecutorMock(c);
        vm.deal(address(this), 1_000_000 ether);
    }
    function _configuration() internal view returns (IYieldManagerV2.Initialization memory c) {
        c = IYieldManagerV2.Initialization(
            address(safe),
            operator,
            address(pool),
            address(boldToken),
            address(sBoldToken),
            address(sink),
            address(rethToken),
            address(ysyToken)
        );
    }
    function _bind() internal {
        vm.prank(address(safe));
        manager.bindVaults(address(rVault), address(yVault));
    }
    function _enable() internal {
        _bind();
        vm.startPrank(address(safe));
        manager.configureExecution(address(execution), 100_000 ether, 100_000 ether, 100_000 ether);
        manager.setExecutionEnabled(true);
        manager.setIntakeEnabled(true);
        vm.stopPrank();
    }
    function _fund(uint256 amount) internal {
        pool.submit{ value: amount }(manager);
    }
    function _callAsOperator(bytes memory data) internal {
        vm.prank(operator);
        (bool ok, bytes memory reason) = address(manager).call(data);
        if (!ok)
            assembly {
                revert(add(reason, 32), mload(reason))
            }
    }
}
