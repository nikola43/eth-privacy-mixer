/* eslint-disable no-undef */
const ethers = require('ethers');
const dotenv = require('dotenv');
dotenv.config();
const abi = require('./abi/abi.json');
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
const fs = require('fs');

async function main() {
    const provider = new ethers.providers.JsonRpcProvider('https://rpc-pulsechain.g4mm4.io');
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    const contract = new ethers.Contract(process.env.CONTRACT_ADDRESS, abi, wallet);

    try {
        while (true) {
            try {
                console.log('Checking for deposits...');
                const block = await provider.getBlock('latest');
                const currentDate = Math.floor(block.timestamp);
                console.log('Current date:', currentDate);

                const totalDeposits = await contract.totalDeposits();
                console.log('Total Deposits:', totalDeposits.toString());

                if (totalDeposits.toString() === '0') {
                    console.log('No deposits found. Waiting for 12 seconds...');
                    await sleep(12000); // wait for 12 seconds before checking again
                    continue;
                }

                for (let i = 0; i < totalDeposits; i++) {
                    try {
                        const depositId = await contract.getDepositIdAt(i);
                        console.log(`Deposit ${i}:`, depositId);

                        // read deposit data from file
                        const depositData = JSON.parse(fs.readFileSync(`./deposits/${depositId}.json`, 'utf8'));
                        for (let j = 0; j < depositData.proofs.length; j++) {
                            try {
                                const proof = depositData.proofs[j];
                                // console.log(`proof ${j}:`, proof);
                                const hasUserWithdrawn = await contract.hasUserWithdrawn(depositData.merkleRoot, proof.address, proof.date);
                                console.log(`hasUserWithdrawn for ${proof.address} on ${proof.date}:`, hasUserWithdrawn);

                                if (hasUserWithdrawn) {
                                    console.log(`User has withdrawn for depositId ${depositId} with address ${proof.address} on date ${proof.date}`);
                                    continue
                                }

                                // console.log({
                                //     merkleRoot: depositData.merkleRoot,
                                //     address: proof.address,
                                //     amount: proof.amount,
                                //     date: proof.date,
                                //     proof: proof.proof
                                // })

                                const shouldTransferEther = await contract.shouldTransferEther(depositData.merkleRoot, proof.address, proof.amount, proof.date, proof.proof);
                                console.log(`shouldTransferEther for ${proof.address} on ${proof.date}:`, shouldTransferEther);

                                if (!shouldTransferEther) {
                                    console.log(`User should not transfer ether for depositId ${depositId} with address ${proof.address} on date ${proof.date}`);
                                    continue
                                }

                                const tx = await contract.transferEther(depositData.merkleRoot, proof.address, proof.amount, Number(proof.date), proof.proof);
                                await tx.wait();
                                console.log(`Transaction successful for depositId ${depositId} with address ${proof.address} on date ${proof.date}`);
                                console.log(`Transaction hash: ${tx.hash}`);
                            } catch (error) {
                                console.error('Error:', error);
                            }
                        }
                    } catch (error) {
                        console.error('Error:', error);
                    }
                }

                await sleep(12000); // wait for 12 seconds before checking again
                console.log('Waiting for 12 seconds before checking again...');
            } catch (error) {
                console.error('Error:', error);
            }
        }

    } catch (error) {
        console.error('Error:', error);
    }
}

main()
    .then(() => console.log('Daemon started'))
    .catch((error) => console.error('Error starting daemon:', error));