const { ethers, upgrades} = require('hardhat');

const path = require('path');
const fs = require('fs');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

const pathOutputJson = path.join(__dirname, '../deploy_output_helper.json');
let deployOutput = {};
if (fs.existsSync(pathOutputJson)) {
  deployOutput = require(pathOutputJson);
}
async function main() {
    // let deployer = new ethers.Wallet(process.env.PRIVATE_KEY, ethers.provider);
    let [owner] = await ethers.getSigners();
    console.log(`Using owner account: ${await owner.getAddress()}`)
    console.log('deployOutput.bitmapRentHelperContract = ', deployOutput.bitmapRentHelperContract)

    const bitmapRentHelperFactory = await ethers.getContractFactory("BitmapRentHelperContract", owner);
   // let bitmapRentHelperContract;
    if (deployOutput.bitmapRentHelperContract === undefined) {
        console.log(`... contract : undefined`)
        bitmapRentHelperContract = await upgrades.deployProxy(
          bitmapRentHelperFactory,
        [],
        {
            initializer: false,
            constructorArgs: [],
            unsafeAllow: ['constructor', 'state-variable-immutable'],
        });
    console.log('tx hash:', bitmapRentHelperContract.deploymentTransaction().hash);
    } else {
      bitmapRentHelperContract = bitmapRentHelperFactory.attach(deployOutput.bitmapRentHelperContract);
    }

    console.log('bitmapRentHelperContract deployed to:', bitmapRentHelperContract.target);
    deployOutput.bitmapRentHelperContract = bitmapRentHelperContract.target;
    fs.writeFileSync(pathOutputJson, JSON.stringify(deployOutput, null, 1));

    const tx = await bitmapRentHelperContract.initialize(process.env.INITIAL_OWNER,
        process.env.BitmapNFT,
        process.env.SwapContract);
    await tx.wait(1);
    console.log("init ok")

    deployOutput.bitmapRentHelperContract = bitmapRentHelperContract.target;
    fs.writeFileSync(pathOutputJson, JSON.stringify(deployOutput, null, 1));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
