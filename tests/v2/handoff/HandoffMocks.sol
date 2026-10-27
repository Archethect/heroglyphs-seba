// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { IEthFlow } from "src/vendor/cowswap/IEthFlow.sol";
import { ExecutorToken } from "../executor/ExecutorMocks.sol";

contract HandoffSafeMock {
    address[] private _owners;
    uint256 public getThreshold = 2;
    bool public module;
    address public nextModule = address(1);
    bytes private _guard = abi.encode(uint256(0));
    constructor() {
        _owners.push(address(0xaaa));
        _owners.push(address(0xbbb));
        _owners.push(address(0xccc));
    }
    function getOwners() external view returns (address[] memory) {
        return _owners;
    }
    function setOwners(address[] calldata owners) external {
        _owners = owners;
    }
    function setThreshold(uint256 n) external {
        getThreshold = n;
    }
    function setModule(bool m, address n) external {
        module = m;
        nextModule = n;
    }
    function setGuard(bytes calldata g) external {
        _guard = g;
    }
    function getModulesPaginated(address, uint256) external view returns (address[] memory a, address) {
        a = new address[](module ? 1 : 0);
        if (module) a[0] = address(123);
        return (a, nextModule);
    }
    function getStorageAt(uint256, uint256) external view returns (bytes memory) {
        return _guard;
    }
}

contract HandoffPoolMock {
    address public yieldManager;
    function setYieldManager(address manager) external {
        yieldManager = manager;
    }
}

contract HandoffRouterMock {
    bool public active;
    function setActive(bool a) external {
        active = a;
    }
    function order() external view returns (address, uint256, bytes32, bool, IEthFlow.Data memory data) {
        return (address(0), 0, bytes32(0), active, data);
    }
}

/// @dev SYNTHETIC adapter: a fixed 50% ETH return proves legacy control flow, not executable mainnet liquidation.
contract HandoffAdapterMock {
    uint256 public principalValue;
    uint256 public principalShares;
    ExecutorToken public beefy;
    constructor() {
        beefy = new ExecutorToken(18);
    }
    function deposit() external payable returns (uint256) {
        principalValue += msg.value;
        principalShares += msg.value;
        beefy.mint(address(this), msg.value);
        return msg.value;
    }
    function seedResidue() external {
        principalValue += 150;
        principalShares += 121;
        beefy.mint(address(this), 121);
    }
    function retrievePrincipal(uint256 amount) external {
        principalValue -= amount;
        principalShares -= amount;
        beefy.transfer(address(0xdead), amount);
        (bool ok, ) = msg.sender.call{ value: amount / 2 }("");
        require(ok, "mock send failed");
    }
}

contract HandoffDestinationMock {
    address public treasury;
    address public sebaPool;
    address public bold;
    address public sBold;
    address public pybSeba;
    bool public intakeEnabled;
    bool public executionEnabled;
    bool public buffersRecovered;
    uint256[3] public pendingEth;
    uint256 public pendingBold;
    uint256 public pendingSBold;
    mapping(uint8 => mapping(uint8 => uint256)) public harvestInventory;
    uint16 public rethBps = 5000;
    uint16 public ysyBoldBps = 5000;
    address public legacyHandoff;
    uint256 public legacyExpectedEth;
    uint256 public legacyExpiry;
    bytes32 public legacyManifest;
    bool public legacyImported;
    bool public rejectImport;
    constructor(address safe, address pool, address b, address s, address pyb) {
        treasury = safe;
        sebaPool = pool;
        bold = b;
        sBold = s;
        pybSeba = pyb;
    }
    receive() external payable {}
    function arm(address source, uint256 amount, uint256 expiry, bytes32 manifest) external {
        legacyHandoff = source;
        legacyExpectedEth = amount;
        legacyExpiry = expiry;
        legacyManifest = manifest;
    }
    function setMode(bool intake, bool execution, bool recovered, bool imported) external {
        intakeEnabled = intake;
        executionEnabled = execution;
        buffersRecovered = recovered;
        legacyImported = imported;
    }
    function setPending(uint8 p, uint256 n) external {
        pendingEth[p] = n;
    }
    function setRewards(uint256 b, uint256 s) external {
        pendingBold = b;
        pendingSBold = s;
    }
    function setHarvest(uint8 leg, uint8 bucket, uint256 n) external {
        harvestInventory[leg][bucket] = n;
    }
    function setWeights(uint16 r, uint16 y) external {
        rethBps = r;
        ysyBoldBps = y;
    }
    function setReject(bool b) external {
        rejectImport = b;
    }
    function importLegacyPrincipal() external payable {
        require(!rejectImport, "synthetic import rejected");
        require(
            msg.sender == legacyHandoff && !legacyImported && msg.value == legacyExpectedEth,
            "synthetic import mismatch"
        );
        legacyImported = true;
        uint256 r = (msg.value * rethBps) / 10000;
        pendingEth[1] += r;
        pendingEth[2] += msg.value - r;
    }
}
