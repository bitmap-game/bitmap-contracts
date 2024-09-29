const { ethers, upgrades} = require('hardhat');

const path = require('path');
const fs = require('fs');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

const pathOutputJson = path.join(__dirname, '../deploy_output_stake.json');
let deployOutput = {};
if (fs.existsSync(pathOutputJson)) {
  deployOutput = require(pathOutputJson);
}
async function main() {
    // let deployer = new ethers.Wallet(process.env.PRIVATE_KEY, ethers.provider);
    let [owner] = await ethers.getSigners();
    console.log(`Using owner account: ${await owner.getAddress()}`)
    console.log('deployOutput.merlStakeContract = ', deployOutput.merlStakeContract)

    const MerlStakeFactory = await ethers.getContractFactory("MerlStake", owner);
   // let merlStakeContract;
    if (deployOutput.merlStakeContract === undefined) {
        console.log(`... contract : undefined`)
      merlStakeContract = await upgrades.deployProxy(
          MerlStakeFactory,
        [],
        {
            initializer: false,
            constructorArgs: [],
            unsafeAllow: ['constructor', 'state-variable-immutable'],
        });
    console.log('tx hash:', merlStakeContract.deploymentTransaction().hash);
    } else {
      merlStakeContract = MerlStakeFactory.attach(deployOutput.merlStakeContract);
    }

    console.log('merlStakeContract deployed to:', merlStakeContract.target);
    deployOutput.merlStakeContract = merlStakeContract.target;
    fs.writeFileSync(pathOutputJson, JSON.stringify(deployOutput, null, 1));

    await sleep(1000*5);

    const tx = await merlStakeContract.initialize(process.env.INITIAL_OWNER,
        process.env.MerlContract);
    await tx.wait(1);
    console.log("init ok")

    deployOutput.merlStakeContract = merlStakeContract.target;
    fs.writeFileSync(pathOutputJson, JSON.stringify(deployOutput, null, 1));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
