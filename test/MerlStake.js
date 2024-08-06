const { expect} = require('chai');
const { ethers } = require("hardhat");


describe("Test MerlStake Contract", function () {
    async function deployFixture() {
        [owner, addr1] = await ethers.getSigners();

        const erc20CapAmount = BigInt("1000000000000000000000000000"); // 1e27 1G
        const approveAmount = BigInt("1000000000000000000000000"); //1e24 1M
        const stakeAmount = BigInt("1000000000000000000") //1e18 1

        const ERC20TokenWrapped = await ethers.getContractFactory("ERC20TokenWrapped", owner);
        Merl = await ERC20TokenWrapped.deploy("bitmapToken", "bitmapToken", 18, erc20CapAmount);

        const MerlStakeContract = await ethers.getContractFactory("MerlStake", owner);
        MerlStake = await MerlStakeContract.deploy();
        await MerlStake.initialize(owner, Merl);

        return {owner, addr1, Merl, MerlStake, approveAmount, stakeAmount};
    }

    describe('deployment', function () {
        it('should set the right owner', async function () {
            const {MerlStake, owner} = await deployFixture();
            expect(await MerlStake.owner()).to.equal(owner.address);
        });
    });

    describe('stakeMerl', function () {
        it('should stakeMerl successful', async function () {
            const {Merl, MerlStake, owner, approveAmount, stakeAmount} = await deployFixture();

            await Merl.connect(owner).approve(MerlStake, approveAmount);
            await Merl.connect(owner).mint(owner, stakeAmount);

            const stakeMerlHash = await MerlStake.connect(owner).stakeMerl(stakeAmount);
            stakeMerlHash.wait()

            let stake = await MerlStake.connect(owner).accountToStake(owner.address)
            let merlAmount = stake[1];
            console.log("stake, merlAmount = ", stake, merlAmount);

            expect(BigInt(merlAmount)).to.equal(stakeAmount);
        });
    });

    describe('unstakeMerl', function () {
        it('should unstakeMerl successful', async function () {
            const {Merl, MerlStake, owner, approveAmount, stakeAmount} = await deployFixture();

            await Merl.connect(owner).approve(MerlStake, approveAmount);
            await Merl.connect(owner).mint(owner, stakeAmount);

            await MerlStake.connect(owner).stakeMerl(stakeAmount);
            const beforeBalance = await Merl.connect(owner).balanceOf(owner.address);
            console.log("beforeBalance = ", beforeBalance);

            const unstakeMerlHash = await MerlStake.connect(owner).unstakeMerl(stakeAmount, false);
            unstakeMerlHash.wait()
            const afterBalance = await Merl.connect(owner).balanceOf(owner.address);
            console.log("afterBalance = ", afterBalance)

            expect(BigInt(beforeBalance)).to.equal(BigInt(afterBalance)-stakeAmount);
            });
    });
})
