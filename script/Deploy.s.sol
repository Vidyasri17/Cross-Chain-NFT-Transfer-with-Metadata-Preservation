// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/CrossChainNFT.sol";
import "../src/CCIPNFTBridge.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Load from env or use defaults (Fuji)
        address router = vm.envAddress("CCIP_ROUTER");
        address linkToken = vm.envAddress("LINK_TOKEN");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy NFT
        CrossChainNFT nft = new CrossChainNFT("CrossChainNFT", "CCNFT", deployer);
        console.log("Deployed NFT at:", address(nft));
        
        // 2. Deploy Bridge
        CCIPNFTBridge bridge = new CCIPNFTBridge(router, linkToken, address(nft), deployer);
        console.log("Deployed Bridge at:", address(bridge));
        
        // 3. Configure NFT to allow bridge to mint
        nft.setBridge(address(bridge));
        console.log("Bridge set in NFT contract.");

        // 4. Pre-mint Test NFT (Token ID 1)
        // Temporarily set bridge to deployer to allow direct minting for setup
        nft.setBridge(deployer);
        nft.mint(deployer, 1, "https://gateway.pinata.cloud/ipfs/QmP3W5vUv9W8jU5p6n9...");
        console.log("Pre-minted Token ID 1 to deployer.");
        
        // Reset bridge to the actual bridge contract
        nft.setBridge(address(bridge));

        vm.stopBroadcast();
    }
}
