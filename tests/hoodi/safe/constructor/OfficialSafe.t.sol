// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/src/Test.sol";

interface IHoodiSafeFactory {
    function createProxyWithNonce(
        address singleton,
        bytes calldata initializer,
        uint256 saltNonce
    )
        external
        returns (address);
}

interface IHoodiSafe {
    function setup(
        address[] calldata owners,
        uint256 threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    )
        external;
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
    function getModulesPaginated(address start, uint256 pageSize) external view returns (address[] memory, address);
    function getStorageAt(uint256 offset, uint256 length) external view returns (bytes memory);
    function nonce() external view returns (uint256);
    function approveHash(bytes32 hashToApprove) external;
    function getTransactionHash(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 nonce_
    )
        external
        view
        returns (bytes32);
    function execTransaction(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    )
        external
        payable
        returns (bool);
}

contract SafeCallerProbe {
    address public lastCaller;

    function mark() external {
        lastCaller = msg.sender;
    }
}

contract OfficialHoodiSafeForkTest is Test {
    address internal constant SINGLETON = 0x41675C099F32341bf84BFc5382aF534df5C7461a;
    address internal constant FACTORY = 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67;
    address internal constant MULTISEND = 0x38869bf66a61cF6bDB996A6aE40D5853Fd43B526;
    address internal constant OWNER = 0x00008A88A21a1d34CDDAA7fC15A0E84ed7e42D8f;
    uint256 internal constant GUARD_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;

    IHoodiSafe internal safe;

    function setUp() public {
        vm.createSelectFork(vm.envString("HOODI_RPC"), 3_988_379);
        assertEq(block.chainid, 560_048);
        assertEq(SINGLETON.codehash, 0x1fe2df852ba3299d6534ef416eefa406e56ced995bca886ab7a553e6d0c5e1c4);
        assertEq(FACTORY.codehash, 0x50c3cdc4074750a7a974204a716c999edd37482f907608d960b2b025ee0b3317);
        assertEq(MULTISEND.codehash, 0x0e4f7fc66550a322d1e7688e181b75e217e662a4f3f4d6a29b22bc61217c4b77);
        address[] memory owners = new address[](1);
        owners[0] = OWNER;
        bytes memory initializer = abi.encodeCall(
            IHoodiSafe.setup, (owners, 1, address(0), bytes(""), address(0), address(0), 0, payable(address(0)))
        );
        safe = IHoodiSafe(IHoodiSafeFactory(FACTORY).createProxyWithNonce(SINGLETON, initializer, 0x5EBA));
    }

    function test_OfficialSafeVersionAndPolicyViews() public view {
        assertEq(safe.getThreshold(), 1);
        address[] memory owners = safe.getOwners();
        assertEq(owners.length, 1);
        assertEq(owners[0], OWNER);
        (address[] memory modules, address next) = safe.getModulesPaginated(address(1), 1);
        assertEq(modules.length, 0);
        assertEq(next, address(1));
        bytes memory guard = safe.getStorageAt(GUARD_SLOT, 1);
        assertEq(guard.length, 32);
        assertEq(abi.decode(guard, (uint256)), 0);
    }

    function test_RealExecTransactionUsesSafeAsCaller() public {
        SafeCallerProbe probe = new SafeCallerProbe();
        bytes memory data = abi.encodeCall(SafeCallerProbe.mark, ());
        bytes32 txHash =
            safe.getTransactionHash(address(probe), 0, data, 0, 0, 0, 0, address(0), address(0), safe.nonce());
        vm.prank(OWNER);
        safe.approveHash(txHash);
        bytes memory signature = abi.encodePacked(bytes32(uint256(uint160(OWNER))), bytes32(0), uint8(1));
        assertTrue(
            safe.execTransaction(address(probe), 0, data, 0, 0, 0, 0, address(0), payable(address(0)), signature)
        );
        assertEq(probe.lastCaller(), address(safe));
        assertEq(safe.nonce(), 1);
    }
}
