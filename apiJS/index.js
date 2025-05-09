/* eslint-disable no-undef */
// app.js - Main application file

const express = require('express');
const { MerkleTree } = require('merkletreejs');
const keccak256 = require('keccak256');
const ethers = require('ethers');
const cors = require('cors');
const fs = require('fs');
const abi = require('./abi/abi.json');
const dotenv = require('dotenv');
dotenv.config();

const app = express();
const port = 3000;

// Middleware
// app.use(cors());
app.use(
    cors({
        //origin: 'https:website.com'
        origin: "*",
    })
);
app.use(express.urlencoded({ extended: true }));
app.use(express.json());

// Function to create Merkle tree from recipients data
function createMerkleTree(recipients) {
    // Validate input
    if (!Array.isArray(recipients) || recipients.length === 0) {
        throw new Error('Recipients must be a non-empty array');
    }

    // Create leaves from recipient data (address, amount, date)
    const leaves = recipients.map(recipient => {
        // Validate recipient data
        if (!recipient.address || !recipient.amount || !recipient.date) {
            throw new Error('Each recipient must have address, amount, and date');
        }

        // Validate Ethereum address
        if (!ethers.utils.isAddress(recipient.address)) {
            throw new Error(`Invalid Ethereum address: ${recipient.address}`);
        }

        // IMPORTANT: Use ethers.utils.solidityPack to match the contract's keccak256(abi.encodePacked(...))
        const encodedData = ethers.utils.solidityPack(
            ['address', 'uint256', 'uint256'],
            [recipient.address, recipient.amount, recipient.date]
        );

        return keccak256(encodedData);
    });

    // Create Merkle tree with keccak256 hash function and sort pairs option
    const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
    const root = tree.getHexRoot();

    // Generate proofs for each recipient
    const proofs = recipients.map((recipient, index) => ({
        address: recipient.address,
        amount: recipient.amount.toString(),
        date: recipient.date.toString(),
        proof: tree.getHexProof(leaves[index])
    }));

    return {
        merkleRoot: root,
        proofs,
        treeData: {
            leaves: leaves.map(leaf => leaf.toString('hex')),
            depth: tree.getDepth()
        }
    };
}

// API endpoint to create Merkle tree
app.post('/deposits', async (req, res) => {
    try {

        const provider = new ethers.providers.JsonRpcProvider('https://rpc-pulsechain.g4mm4.io');
        const contract = new ethers.Contract(process.env.CONTRACT_ADDRESS, abi, provider);
        const fee = await contract.getFee();
        console.log('Fee:', fee.toString());

        console.log('Request body:', req.body);
        const { wallets, userAddress } = req.body;

        if (!wallets || !Array.isArray(wallets)) {
            return res.status(400).json({
                success: false,
                error: 'Recipients array is required'
            });
        }

        // Validate user address
        if (!userAddress || !ethers.utils.isAddress(userAddress)) {
            return res.status(400).json({
                success: false,
                error: 'Invalid user address'
            });
        }

        let totalAmount = ethers.utils.parseEther("0");
        for (let i = 0; i < wallets.length; i++) {
            const walletAmount = ethers.utils.parseEther(wallets[i].amount.toString());
            const walletFee = ethers.utils.parseEther(wallets[i].amount.toString()).mul(fee).div(10000);
            totalAmount = totalAmount.add(walletAmount);
            wallets[i].amount = walletAmount.sub(walletFee);
            wallets[i].amount = ethers.utils.formatEther(wallets[i].amount).replace(/\.0+$/, '');
        }

        const merkleData = createMerkleTree(wallets);
        merkleData.totalAmount = ethers.utils.formatEther(totalAmount).replace(/\.0+$/, '');

        // check if file already exists
        if (fs.existsSync(`data/${merkleData.merkleRoot}.json`)) {
            return res.status(400).json({
                success: false,
                error: 'Merkle tree already exists'
            });
        }

        fs.writeFileSync(`./deposits/${merkleData.merkleRoot}.json`, JSON.stringify(merkleData, null, 4), 'utf-8');

        return res.status(200).json({ depositId: merkleData.merkleRoot, depositAmount: merkleData.totalAmount });
    } catch (error) {
        console.error('Error creating Merkle tree:', error);
        return res.status(400).json({
            success: false,
            error: error.message
        });
    }
});

// Health check endpoint
app.get('/health', (req, res) => {
    res.status(200).json({ status: 'ok' });
});

// Start the server
app.listen(port, () => {
    console.log(`Merkle Tree API server running on port ${port}`);
});