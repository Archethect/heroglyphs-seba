// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockPOAP
 * @notice POAP-like mock allowing storage of an "event ID" per token
 *         and standard NFT functionality for testing.
 */
contract MockPOAP is ERC721URIStorage, Ownable {
    /// @notice Counter for token IDs.
    uint256 public tokenIdCounter;

    /**
     * @notice Mapping from tokenId => event ID (like STAKERS_UNION, etc.)
     *         e.g., if you're checking for a specific event ID = 1234 or a hash.
     */
    mapping(uint256 => uint256) private _tokenEvent;

    constructor(address owner) Ownable(owner) ERC721("MockPOAP", "mPOAP") {}

    /**
     * @notice Create a new “POAP” (NFT) for `_to`, optionally providing a tokenURI and an event ID.
     * @dev    - The `eventId` can be any uint (e.g., some ID or constant representing "STAKERS_UNION").
     *         - If you don’t need a URI, pass an empty string.
     * @param  _to       The recipient address.
     * @param  _tokenURI The metadata URI describing the POAP (event details, images, etc.).
     * @param  eventId   The numeric identifier of the event (e.g. STAKERS_UNION).
     * @return newTokenId The newly minted token ID.
     */
    function createPoap(
        address _to,
        string calldata _tokenURI,
        uint256 eventId
    ) external onlyOwner returns (uint256 newTokenId) {
        newTokenId = ++tokenIdCounter; // Increment, then get new ID
        _safeMint(_to, newTokenId);

        // Store the event ID in our mapping
        _tokenEvent[newTokenId] = eventId;

        // Set token URI if provided
        if (bytes(_tokenURI).length != 0) {
            _setTokenURI(newTokenId, _tokenURI);
        }
    }

    /**
     * @notice Retrieve the event ID (e.g., STAKERS_UNION) for a given token ID.
     * @param tokenId The NFT token ID to look up.
     * @return eventId The event ID associated with that token.
     */
    function tokenEvent(uint256 tokenId) external view returns (uint256 eventId) {
        return _tokenEvent[tokenId];
    }
}
