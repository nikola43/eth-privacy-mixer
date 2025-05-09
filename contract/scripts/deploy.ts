

// @ts-ignore
import { ethers } from 'hardhat';



const main = async () => {
  const signers = await ethers.getSigners();
  const deployer = signers[0];

  console.log(`Deploying contracts with the account: ${deployer.address}`);

  const MixerFactory = await ethers.getContractFactory('MixerMerkleRoot');
  const mixer = await MixerFactory.deploy("0x08BD921f3DDEfCE3956bFD3A76a492A5C1c3F51d")
  await mixer.waitForDeployment();
  console.log(`Mixer deployed to: ${mixer.target}`);

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });







