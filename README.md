# Cross-Chain NFT Bridge using Chainlink CCIP

This project implements a production-ready cross-chain NFT bridge using the burn-and-mint mechanism, powered by Chainlink Cross-Chain Interoperability Protocol (CCIP).

## Project Structure

- `src/`: Solidity smart contracts (`CrossChainNFT.sol`, `CCIPNFTBridge.sol`).
- `script/`: Foundry deployment and configuration scripts.
- `cli/`: Node.js CLI tool for initiating transfers.
- `data/`: JSON files for tracking transfers.
- `logs/`: Transaction logs.
- `Dockerfile` & `docker-compose.yml`: Containerization setup.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Node.js](https://nodejs.org/) (v18+)
- [Docker](https://www.docker.com/)

## Setup

1. Clone the repository.
2. Install dependencies:
   ```bash
   npm install
   ```
3. Copy `.env.example` to `.env` and fill in your details:
   ```bash
   cp .env.example .env
   ```

## Pre-minted Test Asset

For testing purposes, a test NFT has been pre-minted on the source chain (**Avalanche Fuji**):

- **Contract Address**: See `deployment.json` (`avalancheFuji.nftContractAddress`)
- **Token ID**: `1`
- **Owner**: Deployer Address

## Usage

### Running with Docker

1. Build and start the container:
   ```bash
   docker-compose up -d --build
   ```

2. Execute a transfer:
   ```bash
   docker exec ccip-nft-bridge-cli npm run transfer -- --tokenId=1 --from=avalanche-fuji --to=arbitrum-sepolia --receiver=YOUR_WALLET_ADDRESS
   ```

### Running Locally

Execute the transfer script directly:
```bash
npm run transfer -- --tokenId=1 --from=avalanche-fuji --to=arbitrum-sepolia --receiver=YOUR_WALLET_ADDRESS
```

## Contracts

### CrossChainNFT.sol
A standard ERC-721 token with a restricted `mint` function callable only by the bridge. Includes a `burn` function for cross-chain transfers.

### CCIPNFTBridge.sol
Handles the cross-chain logic. Inherits from `CCIPReceiver` to handle incoming messages and uses `IRouterClient` to send messages.

## Monitoring
You can track your cross-chain messages using the [Chainlink CCIP Explorer](https://ccip.chain.link/) by searching for the CCIP Message ID emitted in the bridge logs.
