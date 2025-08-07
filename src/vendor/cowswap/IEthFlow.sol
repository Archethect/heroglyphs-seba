// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IEthFlow {
    struct Data {
        IERC20  buyToken;
        address receiver;
        uint256 sellAmount;          // raw ETH
        uint256 buyAmount;           // min BOLD out
        bytes32 appData;
        uint256 feeAmount;
        uint32  validTo;
        bool    partiallyFillable;   // keep false
        uint64  quoteId;             // 0 if not using off-chain quoting
    }
    function createOrder(Data calldata d) external payable returns (bytes memory uid);
    function cancelOrder(bytes calldata uid) external;
}
