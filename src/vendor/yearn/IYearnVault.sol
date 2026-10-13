// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title IYearnVault
 * @notice Interface for the Yearn V3 vault and tokenized-strategy functions used by Seba.
 */
interface IYearnVault is IERC4626 {
    /**
     * @notice Redeems shares while bounding any loss realized by Yearn.
     * @param shares Shares to redeem.
     * @param receiver Address receiving the underlying asset.
     * @param owner Address whose shares are burned.
     * @param maxLoss Maximum acceptable loss in basis points.
     * @return assets Actual underlying assets returned.
     */
    function redeem(uint256 shares, address receiver, address owner, uint256 maxLoss) external returns (uint256 assets);

    /**
     * @notice Returns the shares currently redeemable at the supplied loss tolerance.
     * @param owner Share owner.
     * @param maxLoss Maximum acceptable loss in basis points.
     * @return shares Maximum redeemable shares.
     */
    function maxRedeem(address owner, uint256 maxLoss) external view returns (uint256 shares);

    /**
     * @notice Reports whether the strategy has been shut down.
     * @return True when new capital cannot safely be deployed.
     */
    function isShutdown() external view returns (bool);
}
