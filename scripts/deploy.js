const { ethers, upgrades} = require('hardhat');

const path = require('path');
const fs = require('fs');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

const pathOutputJson = path.join(__dirname, '../deploy_output.json');
let deployOutput = {};
if (fs.existsSync(pathOutputJson)) {
  deployOutput = require(pathOutputJson);
}
async function main() {
    // let deployer = new ethers.Wallet(process.env.PRIVATE_KEY, ethers.provider);
    let [owner] = await ethers.getSigners();
    console.log(`Using owner account: ${await owner.getAddress()}`)
    console.log('deployOutput.bitmapRentContract = ', deployOutput.bitmapRentContract)

    const BitmapRentFactory = await ethers.getContractFactory("BitmapRent", owner);
   // let bitmapRentContract;
    if (deployOutput.bitmapRentContract === undefined) {
        console.log(`... contract : undefined`)
      bitmapRentContract = await upgrades.deployProxy(
          BitmapRentFactory,
        [],
        {
            initializer: false,
            constructorArgs: [],
            unsafeAllow: ['constructor', 'state-variable-immutable'],
        });
    console.log('tx hash:', bitmapRentContract.deploymentTransaction().hash);
    } else {
      bitmapRentContract = BitmapRentFactory.attach(deployOutput.bitmapRentContract);
    }

    console.log('bitmapRentContract deployed to:', bitmapRentContract.target);
    deployOutput.bitmapRentContract = bitmapRentContract.target;
    fs.writeFileSync(pathOutputJson, JSON.stringify(deployOutput, null, 1));

    const tx = await bitmapRentContract.initialize(process.env.INITIAL_OWNER,
        process.env.BitmapToken,
        process.env.StakeContract,
        process.env.Signer);
    await tx.wait(1);
    console.log("init ok")

    deployOutput.bitmapRentContract = bitmapRentContract.target;
    fs.writeFileSync(pathOutputJson, JSON.stringify(deployOutput, null, 1));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
