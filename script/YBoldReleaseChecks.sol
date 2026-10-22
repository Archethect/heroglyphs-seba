// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IYBoldReleaseSafe {
    function getThreshold() external view returns (uint256);
    function getOwners() external view returns (address[] memory);
    function getModulesPaginated(address start, uint256 pageSize) external view returns (address[] memory, address);
    function getStorageAt(uint256 offset, uint256 length) external view returns (bytes memory);
}

/**
 * @notice Pins the reviewed mainnet authority configuration, not operator-supplied replacement expectations.
 * @dev Inventory at block 26,248,207. Any intentional signer/module/guard change requires a reviewed release update.
 */
library YBoldReleaseChecks {
    address internal constant TREASURY = 0x888D768764A2E304215247F0bA3457cCb0f0ab4f;
    address internal constant GOVERNANCE = 0xf83b11b09EEc073ACE4481b2F4c8357e156714b3;
    uint256 internal constant GUARD_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;

    /// @notice Reverts unless all authority addresses and the exact approved Safe configuration still match.
    function validate(address admin, address upgrader, address recoveryTreasury) internal view {
        require(admin == GOVERNANCE && upgrader == TREASURY && recoveryTreasury == TREASURY, "RELEASE_AUTHORITIES");
        IYBoldReleaseSafe safe = IYBoldReleaseSafe(TREASURY);
        require(safe.getThreshold() == 3, "RELEASE_SAFE_THRESHOLD");
        address[] memory owners = new address[](7);
        owners[0] = 0xC87dF2dA974a718Dd6ca95f7e92E643437d69Fea;
        owners[1] = 0xf67a4a4CCcfcB1496d6d699Eee33a4b072833d9d;
        owners[2] = 0x33278e8e62540BA7bCc2Ec46Ab94931B8Fb7A92B;
        owners[3] = 0xd380B2032cD45286D922dD9b33D081B7D82D54A6;
        owners[4] = 0xFe7E12FB4f5BE7a49B2D7a8FE676CFc38FaF7e81;
        owners[5] = 0x6271235f2A5357c38E5742ada38895347401Ef49;
        owners[6] = 0x2BE293361aEA6136a42036Ef68FF248fC379b4f8;
        require(keccak256(abi.encode(safe.getOwners())) == keccak256(abi.encode(owners)), "RELEASE_SAFE_OWNERS");
        (address[] memory modules, address next) = safe.getModulesPaginated(address(1), 32);
        require(modules.length == 0 && next == address(1), "RELEASE_SAFE_MODULES");
        bytes memory guard = safe.getStorageAt(GUARD_SLOT, 1);
        require(guard.length == 32 && abi.decode(guard, (uint256)) == 0, "RELEASE_SAFE_GUARD");
    }
}
