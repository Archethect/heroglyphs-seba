// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IV2SupporterVault } from "../../../src/interfaces/v2/IV2SupporterVault.sol";
import { RethSupporterVault } from "../../../src/v2/RethSupporterVault.sol";
import { YsyBoldSupporterVault } from "../../../src/v2/YsyBoldSupporterVault.sol";

contract VaultMockSafe {}

contract VaultMockManager {
    mapping(uint8 => uint256) public received;
    bool public reject;
    address public reenter;
    bytes public reentryData;
    function configure(bool fail, address target, bytes calldata data) external {
        reject = fail;
        reenter = target;
        reentryData = data;
    }
    function onYieldReceived(uint8 bucket, uint256 q) external {
        require(!reject, "callback unavailable");
        received[bucket] += q;
        if (reenter != address(0)) {
            (bool ok, ) = reenter.call(reentryData);
            require(ok, "reentry rejected");
        }
    }
}

contract VaultMockToken is ERC20 {
    uint256 public fee;
    bool public fail;
    uint8 public tokenDecimals = 18;
    address public denied;
    address public hook;
    bytes public hookData;
    uint8 public mutation;
    constructor() ERC20("Native custody test token", "NATIVE") {}
    function mint(address to, uint256 q) external {
        _mint(to, q);
    }
    function burn(address from, uint256 q) external {
        _burn(from, q);
    }
    function setFee(uint256 q) external {
        fee = q;
    }
    function setFail(bool value) external {
        fail = value;
    }
    function setDenied(address who) external {
        denied = who;
    }
    function setDecimals(uint8 value) external {
        tokenDecimals = value;
    }
    function setMutation(uint8 value) external {
        mutation = value;
    }
    function setHook(address target, bytes calldata data) external {
        hook = target;
        hookData = data;
    }
    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }
    function _update(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0)) {
            require(!fail && to != denied, "transfer unavailable");
            if (hook != address(0)) {
                (bool ok, ) = hook.call(hookData);
                require(ok, "reentry rejected");
            }
            if (fee != 0) {
                super._update(from, address(0), fee);
                amount -= fee;
            }
        }
        super._update(from, to, amount);
        if (from != address(0) && to != address(0)) {
            // Explicit nonstandard-token fault injection for each exact-delta defensive boundary.
            if (mutation == 1) super._update(to, address(0), amount + 1);
            if (mutation == 2) super._update(address(0), from, amount + 1);
            if (mutation == 3) super._update(from, address(0), 1);
            if (mutation == 4) super._update(to, address(0), amount + 1);
            if (mutation == 5) super._update(address(0), to, 1);
        }
    }
}

contract VaultMockBalances {
    uint256 public numerator = 1 ether;
    uint256 public denominator = 1 ether;
    uint256 public timestamp;
    uint256 public number;
    bool public fail;
    constructor() {
        timestamp = block.timestamp;
        number = block.number;
    }
    function setRate(uint256 n, uint256 d) external {
        numerator = n;
        denominator = d;
    }
    function setReport(uint256 t, uint256 b) external {
        timestamp = t;
        number = b;
    }
    function setFail(bool value) external {
        fail = value;
    }
    function getTotalETHBalance() external view returns (uint256) {
        require(!fail, "valuation unavailable");
        return numerator;
    }
    function getTotalRETHSupply() external view returns (uint256) {
        require(!fail, "valuation unavailable");
        return denominator;
    }
    function getBalancesTimestamp() external view returns (uint256) {
        return timestamp;
    }
    function getBalancesBlock() external view returns (uint256) {
        return number;
    }
}

contract VaultMockRegistry {
    address public token;
    address public balances;
    constructor(address t, address b) {
        token = t;
        balances = b;
    }
    function set(address t, address b) external {
        token = t;
        balances = b;
    }
    function getAddress(bytes32 key) external view returns (address) {
        if (key == keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))) return token;
        return balances;
    }
}

contract VaultMockYearn is VaultMockToken {
    address public asset;
    uint256 public backing = 1 ether;
    uint256 public supply = 1 ether;
    bool public unavailable;
    string public apiVersion = "3.0.4";
    constructor(address ybold) {
        asset = ybold;
    }
    function totalAssets() external view returns (uint256) {
        require(!unavailable, "yearn accounting unavailable");
        return backing;
    }
    function totalSupply() public view override returns (uint256) {
        return supply;
    }
    function setRate(uint256 a, uint256 t) external {
        backing = a;
        supply = t;
    }
    function setUnavailable(bool value) external {
        unavailable = value;
    }
    function setAsset(address value) external {
        asset = value;
    }
    function setVersion(string calldata value) external {
        apiVersion = value;
    }
}

contract VaultRethUpgrade is RethSupporterVault {
    function releaseVersion() external pure returns (uint256) {
        return 2;
    }
}

abstract contract VaultBaseTest is Test {
    VaultMockSafe internal safe;
    VaultMockManager internal coordinator;
    VaultMockToken internal token;
    VaultMockToken internal ybold;
    VaultMockBalances internal balances;
    VaultMockRegistry internal registry;
    VaultMockYearn internal yearn;
    RethSupporterVault internal vault;
    YsyBoldSupporterVault internal yvault;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal operator = address(0x0B07);
    bytes32 internal evidence = keccak256("frozen public custody manifest");
    bytes32 internal classification = keccak256("fixed public budget manifest");

    function setUp() public virtual {
        vm.roll(26_000_000);
        safe = new VaultMockSafe();
        coordinator = new VaultMockManager();
        token = new VaultMockToken();
        ybold = new VaultMockToken();
        balances = new VaultMockBalances();
        registry = new VaultMockRegistry(address(token), address(balances));
        yearn = new VaultMockYearn(address(ybold));
        vault = RethSupporterVault(
            address(
                new ERC1967Proxy(
                    address(new RethSupporterVault()),
                    abi.encodeCall(
                        RethSupporterVault.initialize,
                        (address(safe), address(coordinator), address(token), address(registry))
                    )
                )
            )
        );
        yvault = YsyBoldSupporterVault(
            address(
                new ERC1967Proxy(
                    address(new YsyBoldSupporterVault()),
                    abi.encodeCall(
                        YsyBoldSupporterVault.initialize,
                        (address(safe), address(coordinator), address(yearn), address(ybold))
                    )
                )
            )
        );
        vm.startPrank(address(safe));
        vault.configureReportBounds(2 days, 20_000);
        vault.configureEntry(1, true);
        vault.configureHarvest(type(uint256).max, true);
        vault.setOperator(operator, true);
        yvault.configureEntry(1, true);
        yvault.configureHarvest(type(uint256).max, true);
        vm.stopPrank();
    }

    function _deposit(address owner, uint256 q) internal returns (uint256 id, uint256 b) {
        token.mint(owner, q);
        vm.startPrank(owner);
        token.approve(address(vault), q);
        (id, b) = vault.deposit(q, 0, block.timestamp);
        vm.stopPrank();
    }
    function _yDeposit(address owner, uint256 q) internal returns (uint256 id, uint256 b) {
        yearn.mint(owner, q);
        vm.startPrank(owner);
        yearn.approve(address(yvault), q);
        (id, b) = yvault.deposit(q, 0, block.timestamp);
        vm.stopPrank();
    }
    function _protocol(uint256 q) internal returns (uint256 b) {
        token.mint(address(coordinator), q);
        vm.startPrank(address(coordinator));
        token.approve(address(vault), q);
        b = vault.depositProtocol(q, 0, block.timestamp);
        vm.stopPrank();
    }
    function _unlock() internal {
        vm.warp(block.timestamp + 30 days);
    }
    function _fresh() internal {
        balances.setReport(block.timestamp, block.number);
    }
    function _recover() internal {
        vm.prank(address(safe));
        vault.beginRecovery(evidence);
    }
    function _fund(uint8 which, uint256 q, bool isRepair) internal {
        if (isRepair) token.mint(address(safe), q);
        vm.startPrank(address(safe));
        token.approve(address(vault), q);
        if (isRepair) vault.repairRecovery(which, q);
        else vault.fundRecovery(which, q);
        vm.stopPrank();
    }
    function _activate(uint256 s, uint256 p, bool exceptional) internal {
        uint256[2] memory budgets = [s, p];
        vm.prank(address(safe));
        if (exceptional) vault.activateExceptionalSettlement(budgets, classification);
        else vault.activateSettlement(budgets, classification);
    }
    function _expect(bytes4 error) internal {
        vm.expectRevert(error);
    }
}
