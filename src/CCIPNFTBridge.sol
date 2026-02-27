// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "./CrossChainNFT.sol";

/**
 * @title CCIPNFTBridge
 * @dev Handles sending and receiving NFTs across chains using Chainlink CCIP.
 */
contract CCIPNFTBridge is CCIPReceiver, IERC721Receiver, Ownable {
    // Contract dependencies
    CrossChainNFT public immutable nft;
    IRouterClient public router;
    IERC20 public linkToken;

    // Mapping to store peer bridge addresses on other chains
    mapping(uint64 => address) public peerBridges;

    // Events
    event NFTSent(
        bytes32 messageId,
        uint64 destinationChainSelector,
        address receiver,
        uint256 tokenId,
        string tokenURI
    );

    event NFTReceived(
        bytes32 messageId,
        uint64 sourceChainSelector,
        address sender,
        uint256 tokenId
    );

    constructor(
        address _router,
        address _link,
        address _nft,
        address _owner
    ) CCIPReceiver(_router) Ownable(_owner) {
        router = IRouterClient(_router);
        linkToken = IERC20(_link);
        nft = CrossChainNFT(_nft);
    }

    /**
     * @dev Sets the bridge address for a specific destination chain.
     */
    function setPeerBridge(uint64 chainSelector, address bridgeAddress) external onlyOwner {
        peerBridges[chainSelector] = bridgeAddress;
    }

    /**
     * @dev Main function to initiate the NFT transfer.
     * The NFT must be burned on the source chain.
     */
    function sendNFT(
        uint64 destinationChainSelector,
        address receiver,
        uint256 tokenId
    ) external returns (bytes32 messageId) {
        address peerBridge = peerBridges[destinationChainSelector];
        require(peerBridge != address(0), "Peer bridge not set");
        require(nft.ownerOf(tokenId) == msg.sender, "Ownership check: Caller must be owner of NFT");

        string memory tokenURI = nft.tokenURI(tokenId);

        // Record the transfer details before burning (optional but good for event)
        // Burn the NFT. The bridge must be approved for the tokenId.
        // The sender calls sendNFT, so the bridge needs approval to call nft.burn.
        // Wait, nft.burn checks _msgSender(). If bridge calls nft.burn, msg.sender is bridge.
        // So user must approve bridge for tokenId.
        nft.burn(tokenId);

        // Prepare the CCIP message
        bytes memory data = abi.encode(receiver, tokenId, tokenURI);
        
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(peerBridge),
            data: data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 400_000}) // Increased gas limit for minting
            ),
            feeToken: address(linkToken)
        });

        uint256 fee = router.getFee(destinationChainSelector, message);
        require(linkToken.balanceOf(address(this)) >= fee, "Insufficient fees in bridge");
        
        linkToken.approve(address(router), fee);
        messageId = router.ccipSend(destinationChainSelector, message);

        emit NFTSent(messageId, destinationChainSelector, receiver, tokenId, tokenURI);
    }

    /**
     * @dev Callback function to receive messages from CCIP Router.
     */
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        // Validate source bridge
        address sourceBridge = abi.decode(message.sender, (address));
        require(sourceBridge == peerBridges[message.sourceChainSelector], "Unauthorized source bridge");

        (address receiver, uint256 tokenId, string memory tokenURI) = abi.decode(message.data, (address, uint256, string));
        
        // Idempotency check: tokenURI() reverts if token doesn't exist
        // In CCIPReceiver, failure reverts the message, allowing for retry or manual execution if needed.
        // But here we want to ensure we don't duplicate. ERC-721 mint handles duplicates.
        nft.mint(receiver, tokenId, tokenURI);

        emit NFTReceived(message.messageId, message.sourceChainSelector, sourceBridge, tokenId);
    }

    /**
     * @dev Estimate transfer cost in LINK tokens.
     */
    function estimateTransferCost(
        uint64 destinationChainSelector
    ) external view returns (uint256) {
        address peerBridge = peerBridges[destinationChainSelector];
        if (peerBridge == address(0)) return 0;

        // Use placeholders for estimation as signature is limited
        address receiver = address(0);
        uint256 tokenId = 0;
        string memory tokenURI = "";

        bytes memory data = abi.encode(receiver, tokenId, tokenURI);
        
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(peerBridge),
            data: data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 400_000})
            ),
            feeToken: address(linkToken)
        });

        return router.getFee(destinationChainSelector, message);
    }

    // Required for safe NFT transfers to this contract (if we ever receive them instead of burning)
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // Allow withdrawing tokens (fees or accidental transfers)
    function withdrawToken(address _token, address _to) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(_to, amount);
    }
}
