const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');
const yargs = require('yargs/yargs');
const { hideBin } = require('yargs/helpers');
const { v4: uuidv4 } = require('uuid');
require('dotenv').config();

// Chain configurations
const chains = {
    'avalanche-fuji': {
        name: 'Avalanche Fuji',
        rpc: process.env.FUJI_RPC_URL,
        chainId: 43113,
        selector: process.env.CCIP_ROUTER_FUJI_SELECTOR || '14767482510784806043'
    },
    'arbitrum-sepolia': {
        name: 'Arbitrum Sepolia',
        rpc: process.env.ARBITRUM_SEPOLIA_RPC_URL,
        chainId: 421614,
        selector: process.env.CCIP_ROUTER_ARBITRUM_SEPOLIA_SELECTOR || '3478487238524512106'
    }
};

async function main() {
    const argv = yargs(hideBin(process.argv))
        .option('tokenId', { type: 'string', demandOption: true })
        .option('from', { type: 'string', demandOption: true })
        .option('to', { type: 'string', demandOption: true })
        .option('receiver', { type: 'string', demandOption: true })
        .argv;

    const { tokenId, from, to, receiver } = argv;

    if (!chains[from] || !chains[to]) {
        console.error('Invalid chain selection. Supported: avalanche-fuji, arbitrum-sepolia');
        process.exit(1);
    }

    const provider = new ethers.providers.JsonRpcProvider(chains[from].rpc);
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

    // Load deployment info
    const deploymentPath = path.join(__dirname, '..', 'deployment.json');
    if (!fs.existsSync(deploymentPath)) {
        console.error('deployment.json not found');
        process.exit(1);
    }
    const deployments = JSON.parse(fs.readFileSync(deploymentPath, 'utf8'));

    const sourceDeployment = from === 'avalanche-fuji' ? deployments.avalancheFuji : deployments.arbitrumSepolia;
    const destDeployment = to === 'avalanche-fuji' ? deployments.avalancheFuji : deployments.arbitrumSepolia;

    // ABIs (Simplified for this script, in production use full ABIs)
    const bridgeAbi = [
        "function sendNFT(uint64 destinationChainSelector, address receiver, uint256 tokenId) external returns (bytes32 messageId)",
        "function estimateTransferCost(uint64 destinationChainSelector, address receiver, uint256 tokenId) external view returns (uint256)",
        "event NFTSent(bytes32 messageId, uint64 destinationChainSelector, address receiver, uint256 tokenId, string tokenURI)"
    ];
    const nftAbi = [
        "function approve(address to, uint256 tokenId) external",
        "function getApproved(uint256 tokenId) external view returns (address)",
        "function tokenURI(uint256 tokenId) external view returns (string)",
        "function name() external view returns (string)",
        "function ownerOf(uint256 tokenId) external view returns (address)"
    ];
    const linkAbi = [
        "function approve(address spender, uint256 amount) external returns (bool)",
        "function balanceOf(address account) external view returns (uint256)"
    ];

    const bridgeContract = new ethers.Contract(sourceDeployment.bridgeContractAddress, bridgeAbi, wallet);
    const nftContract = new ethers.Contract(sourceDeployment.nftContractAddress, nftAbi, wallet);

    console.log(`Checking NFT ownership and approval for tokenId ${tokenId}...`);
    const owner = await nftContract.ownerOf(tokenId);
    if (owner.toLowerCase() !== wallet.address.toLowerCase()) {
        throw new Error(`Caller is not the owner of tokenId ${tokenId}. Owner is ${owner}`);
    }

    const approved = await nftContract.getApproved(tokenId);
    if (approved.toLowerCase() !== sourceDeployment.bridgeContractAddress.toLowerCase()) {
        console.log("Approving bridge to burn NFT...");
        const tx = await nftContract.approve(sourceDeployment.bridgeContractAddress, tokenId);
        await tx.wait();
        console.log("Approval confirmed.");
    }

    console.log(`Initiating transfer from ${from} to ${to}...`);

    // Log start
    const logMessage = `[${new Date().toISOString()}] Initiating transfer: Token ${tokenId} from ${from} to ${to} for receiver ${receiver}\n`;
    fs.appendFileSync(path.join(__dirname, '..', 'logs', 'transfers.log'), logMessage);

    // Estimate cost
    const destSelector = chains[to].selector;
    const cost = await bridgeContract.estimateTransferCost(destSelector, receiver, tokenId);
    console.log(`Estimated cost: ${ethers.utils.formatEther(cost)} LINK`);

    // Execute transfer
    const tx = await bridgeContract.sendNFT(destSelector, receiver, tokenId);
    console.log(`Transaction sent: ${tx.hash}`);

    // Save to data file
    const transferEntry = {
        transferId: uuidv4(),
        tokenId: tokenId,
        sourceChain: from,
        destinationChain: to,
        sender: wallet.address,
        receiver: receiver,
        ccipMessageId: "", // Will be filled from logs
        sourceTxHash: tx.hash,
        destinationTxHash: null,
        status: 'initiated',
        metadata: {
            name: "CrossChainNFT #" + tokenId,
            description: "Cross-chain transferred NFT",
            image: "" // Would get from tokenURI normally
        },
        timestamp: new Date().toISOString()
    };

    const receipt = await tx.wait();
    console.log("Transaction confirmed on source chain.");

    // Extract MessageId from events
    const event = receipt.logs.find(log => {
        try {
            const parsed = bridgeContract.interface.parseLog(log);
            return parsed.name === 'NFTSent';
        } catch (e) {
            return false;
        }
    });

    if (event) {
        const parsed = bridgeContract.interface.parseLog(event);
        transferEntry.ccipMessageId = parsed.args.messageId;
        console.log(`CCIP Message ID: ${transferEntry.ccipMessageId}`);
    }

    // Update log and data
    const successMsg = `[${new Date().toISOString()}] Transfer initiated successfully. Source Tx: ${tx.hash}, CCIP Message ID: ${transferEntry.ccipMessageId}\n`;
    fs.appendFileSync(path.join(__dirname, '..', 'logs', 'transfers.log'), successMsg);

    const dataPath = path.join(__dirname, '..', 'data', 'nft_transfers.json');
    let historicalData = [];
    if (fs.existsSync(dataPath)) {
        const content = fs.readFileSync(dataPath, 'utf8');
        historicalData = content ? JSON.parse(content) : [];
    }
    historicalData.push(transferEntry);
    fs.writeFileSync(dataPath, JSON.stringify(historicalData, null, 2));

    console.log("Transfer record saved to data/nft_transfers.json");
}

main().catch(err => {
    console.error("Transfer failed:", err.message);
    fs.appendFileSync(path.join(__dirname, '..', 'logs', 'transfers.log'), `[${new Date().toISOString()}] Transfer failed: ${err.message}\n`);
    process.exit(1);
});
