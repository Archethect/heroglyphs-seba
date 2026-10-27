// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/src/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { RethSupporterVault } from "../../../../src/v2/RethSupporterVault.sol";

contract VaultToken is ERC20 {
    constructor() ERC20("Test native token", "NATIVE") {}
    function mint(address to, uint256 q) external {
        _mint(to, q);
    }
}

contract VaultSafe {}

contract VaultRegistry {
    address public token;
    address public balances;
    constructor(address t, address b) {
        token = t;
        balances = b;
    }
    function getAddress(bytes32 key) external view returns (address) {
        if (key == keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))) return token;
        return balances;
    }
}

contract VaultBalances {
    uint256 public numerator = 11 ether;
    uint256 public denominator = 10 ether;
    function getTotalETHBalance() external view returns (uint256) {
        return numerator;
    }
    function getTotalRETHSupply() external view returns (uint256) {
        return denominator;
    }
    function getBalancesTimestamp() external view returns (uint256) {
        return block.timestamp;
    }
    function getBalancesBlock() external view returns (uint256) {
        return block.number;
    }
}

contract VaultDepositTest is Test {
    function test_GivenEnabledEntry_WhenDepositingNativeTokens_ItCreatesLockedETHBasisWithoutLiquidating() external {
        VaultToken token = new VaultToken();
        VaultSafe safe = new VaultSafe();
        VaultBalances balances = new VaultBalances();
        VaultRegistry registry = new VaultRegistry(address(token), address(balances));
        RethSupporterVault implementation = new RethSupporterVault();
        RethSupporterVault vault = RethSupporterVault(
            address(
                new ERC1967Proxy(
                    address(implementation),
                    abi.encodeCall(
                        RethSupporterVault.initialize,
                        (address(safe), address(this), address(token), address(registry))
                    )
                )
            )
        );
        vm.startPrank(address(safe));
        vault.configureReportBounds(2 days, 20_000);
        vault.configureEntry(1 ether, true);
        vm.stopPrank();
        token.mint(address(this), 100 ether);
        token.approve(address(vault), 100 ether);
        (uint256 id, uint256 basis) = vault.deposit(100 ether, 110 ether, block.timestamp);
        assertEq(basis, 110 ether);
        assertEq(token.balanceOf(address(vault)), 100 ether);
        vm.expectRevert();
        vault.withdraw(id, 0, block.timestamp);
    }
}
