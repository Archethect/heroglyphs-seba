// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockERC721 is ERC721Enumerable {
    uint256 public tokenId;

    constructor() ERC721("TestToken ERC721", "TTERC721") {
        tokenId = 1;
    }

    function mint(address receiver) public {
        _safeMint(receiver, tokenId);
        tokenId++;
    }
}
