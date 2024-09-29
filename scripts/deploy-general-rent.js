const { ethers, upgrades} = require('hardhat');

const path = require('path');
const fs = require('fs');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

const pathOutputJson = path.join(__dirname, '../deploy_output_general_rent.json');
let deployOutput = {};
if (fs.existsSync(pathOutputJson)) {
  deployOutput = require(pathOutputJson);
}
async function main() {
    // let deployer = new ethers.Wallet(process.env.PRIVATE_KEY, ethers.provider);
    let [owner] = await ethers.getSigners();
    console.log(`Using owner account: ${await owner.getAddress()}`)
    console.log('deployOutput.generalRentContract = ', deployOutput.generalRentContract)

    const GeneralRentFactory = await ethers.getContractFactory("GeneralRent", owner);
   // let generalRentContract;
    if (deployOutput.generalRentContract === undefined) {
        console.log(`... contract : undefined`)
      generalRentContract = await upgrades.deployProxy(
          GeneralRentFactory,
        [],
        {
            initializer: false,
            constructorArgs: [],
            unsafeAllow: ['constructor', 'state-variable-immutable'],
        });
    console.log('tx hash:', generalRentContract.deploymentTransaction().hash);
    } else {
      generalRentContract = GeneralRentFactory.attach(deployOutput.generalRentContract);
    }

    console.log('generalRentContract deployed to:', generalRentContract.target);
    deployOutput.generalRentContract = generalRentContract.target;
    fs.writeFileSync(pathOutputJson, JSON.stringify(deployOutput, null, 1));

    const tx = await generalRentContract.initialize(process.env.INITIAL_OWNER,
        process.env.StakeContract,
        process.env.Signer,
        process.env.RentToken,
        process.env.OnePropsAmount);
    await tx.wait(1);
    console.log("init ok")
    console.log("...", process.env.INITIAL_OWNER,
        process.env.StakeContract,
        process.env.Signer,
        process.env.RentToken,
        process.env.OnePropsAmount)


    deployOutput.generalRentContract = generalRentContract.target;
    fs.writeFileSync(pathOutputJson, JSON.stringify(deployOutput, null, 1));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
