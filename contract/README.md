# Ethereum Privacy Mixer with Merkle Proofs

A secure, decentralized solution for preserving transaction privacy on Ethereum and Ethereum-compatible blockchains like PulseChain. This project combines a Solidity smart contract with a Node.js backend to create a privacy-preserving ETH mixer using Merkle trees.

## 🔐 How It Works

1. **Deposit ETH**: Users deposit ETH into the contract along with a Merkle root that represents multiple potential recipients (with addresses, amounts, and time locks).
2. **Privacy Preservation**: The deposit is stored on-chain, but recipient details remain private.
3. **Scheduled Withdrawals**: Authorized withdrawals can only occur:
   - To addresses included in the original Merkle tree
   - After specified time locks expire
   - With valid cryptographic proofs

## 🌟 Key Features

- **Cryptographic Privacy**: Uses Merkle trees to validate withdrawals without revealing all recipients
- **Time-Locked Withdrawals**: Configurable release schedules for funds
- **Role-Based Access**: Admin/Owner separation with granular permissions
- **Emergency Controls**: Safety features including pause functionality and recovery options
- **Flexible Fee Structure**: Configurable fee system (1% default, capped at 10%)

## 📋 Technical Architecture

### Smart Contract (`MixerMerkleRoot.sol`)
- **Framework**: Solidity 0.8.20 with OpenZeppelin libraries
- **Security**: ReentrancyGuard, AccessControl, Checks-Effects-Interactions pattern
- **Storage**: Efficient EnumerableSet for deposit tracking
- **Verification**: MerkleProof verification for secure withdrawals

### Backend API (`app.js`)
- **Framework**: Express.js
- **Cryptography**: Uses merkletreejs and keccak256 for tree generation
- **Blockchain Integration**: ethers.js for contract interaction
- **Utilities**: CORS support, environment variable management

## 🚀 Getting Started

### Prerequisites
- Node.js (v14+)
- NPM or Yarn
- Ethereum wallet with ETH/PLS

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/eth-privacy-mixer.git
cd eth-privacy-mixer

# Install dependencies
npm install

# Set up environment variables
cp .env.example .env
# Edit .env with your contract address and other settings

# Start the server
npm start
```

## 🔧 API Usage

### Create Deposit with Multiple Recipients

```javascript
// Example API call to create a deposit with multiple recipients
fetch('http://localhost:3000/deposits', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    userAddress: '0xYourAddress',
    wallets: [
      { address: '0xRecipient1', amount: '0.1', date: Math.floor(Date.now() / 1000) + 86400 }, // Tomorrow
      { address: '0xRecipient2', amount: '0.2', date: Math.floor(Date.now() / 1000) + 172800 } // Day after tomorrow
    ]
  })
})
.then(response => response.json())
.then(data => console.log('Deposit ID:', data.depositId));
```

### Making a Deposit On-Chain

```javascript
// After getting depositId from the API
const depositId = '0x123...'; // Merkle root from API
const amount = ethers.utils.parseEther('0.5'); // Total amount (sum of all recipients + fee)

const tx = await contract.deposit(depositId, { value: amount });
await tx.wait();
```

## 🛡️ Security Considerations

- Contract includes protection against:
  - Reentrancy attacks
  - Front-running
  - Unauthorized withdrawals
  - Double-spending attempts
- Follows best practices:
  - Checks-Effects-Interactions pattern
  - Proper event emissions
  - Access control validation

## 📊 Fee Structure

The contract charges a small fee on deposits to ensure sustainability:
- Default fee: 1% (100 basis points)
- Maximum fee: 10% (1000 basis points)
- Fee recipient: Configurable by the owner

## 🔄 Workflow Diagram

```
User                           Backend API                          Smart Contract
 |                                 |                                      |
 |-- Request deposit with list --->|                                      |
 |   of recipients                 |                                      |
 |                                 |-- Generate Merkle tree ----------->  |
 |                                 |   for recipients                     |
 |<-- Return depositId ------------|                                      |
 |                                 |                                      |
 |-- Make deposit with depositId ---------------------------------->     |
 |   and ETH value                 |                                      |
 |                                 |                                      |
 |                    ... Time passes until release date ...             |
 |                                 |                                      |
 |                        Admin with proof                               |
 |-- Request withdrawal with proof ---------------------------->         |
 |   to recipient                  |                                      |
 |                                 |                                     |
 |<-- Receive ETH ----------------------------------------------        |
```

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request