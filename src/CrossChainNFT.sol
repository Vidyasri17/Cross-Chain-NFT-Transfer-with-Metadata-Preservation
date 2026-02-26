// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CrossChainNFT
 * @dev An ERC-721 token that can be minted by a bridge and burned by its owner for cross-chain transfer.
 */
contract CrossChainNFT is ERC721URIStorage, Ownable {
    address public bridge;

    constructor(string memory name, string memory symbol, address initialOwner)
        ERC721(name, symbol)
        Ownable(initialOwner)
    {}

    // Modifier to allow only the bridge to call a function
    modifier onlyBridge() {
        require(msg.sender == bridge, "Caller is not the bridge");
        _;
    }

    // Function to set the bridge address
    function setBridge(address _bridge) external onlyOwner {
        bridge = _bridge;
    }

    // Mint a new NFT with a specific token URI. Only callable by the bridge.
    function mint(address to, uint256 tokenId, string memory tokenURI)
        external
        onlyBridge
    {
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
    }

    // Burn an existing NFT. Only callable by the token owner.
    function burn(uint256 tokenId) external {
        // In OZ 5.x, _isApprovedOrOwner is removed. 
        // We check if the caller is the owner or approved.
        address owner = ownerOf(tokenId);
        require(
            _msgSender() == owner || isApprovedForAll(owner, _msgSender()) || getApproved(tokenId) == _msgSender(),
            "ERC721: caller is not token owner or approved"
        );
        _burn(tokenId);
    }
}
