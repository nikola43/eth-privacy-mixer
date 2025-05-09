

// @ts-ignore
import { ethers } from 'hardhat';



const main = async () => {
  const signers = await ethers.getSigners();
  const deployer = signers[0];

  const MixerFactory = await ethers.getContractAt('Mixer', "0x68b808ACbb6beb6866e36249ed4a70a6955Cdbe7");
  const depositTx = await MixerFactory.deposit("0x35c023734a6c2c24771e63f0a8ba26584d21ecdf8e5c696d093cd3a2c16ac661", {
    value: "1001000000000000000000",
  });
  console.log(`Deposit transaction hash: ${depositTx.hash}`);
  const depositReceipt = await depositTx.wait();

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });







