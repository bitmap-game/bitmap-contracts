const { expect} = require('chai');
const { ethers } = require("hardhat");
const {sleep} = require("@nomicfoundation/hardhat-verify/internal/utilities");
const {bigint} = require("hardhat/internal/core/params/argumentTypes");
const {address} = require("hardhat/internal/core/config/config-validation");
const { renterRequest } = require("./common");

describe("Test GeneralRent Contract", function () {
    async function deployFixture() {
        const erc20CapAmount = BigInt("1000000000000000000000000000"); // 1e27 1G
        const approveAmount = BigInt("1000000000000000000000000"); //1e24 1M
        const signAddress = "0xA017e1D6594dBD6b849F1911632e95ca59b41090"
        const merlStakeAddress = "0x0000000000000000000000000000000000000001"

        //owner
        let [owner, addr1] = await ethers.getSigners();

        //rentToken
        const ERC20TokenWrapped = await ethers.getContractFactory("ERC20TokenWrapped", owner);
        const rentToken = await ERC20TokenWrapped.deploy("rentToken", "rentToken", 18, erc20CapAmount);
        const requiredDepositPerProp = BigInt("10000000000000000000000"); //1e22 10K

        //GeneralRent
        const generalRentContract = await ethers.getContractFactory("GeneralRent", owner);
        const GeneralRent = await generalRentContract.deploy();
        await GeneralRent.initialize(owner.address, merlStakeAddress, signAddress, rentToken.getAddress(), requiredDepositPerProp);

        //approve
        await rentToken.connect(owner).approve(GeneralRent, approveAmount);
        await rentToken.connect(owner).mint(owner, approveAmount);

        return {owner, addr1, approveAmount, GeneralRent: GeneralRent, RentToken: rentToken};
    }

    describe('deployment', function () {
        it('should set the right owner', async function () {
            const {owner,GeneralRent } = await deployFixture();
            const own = await GeneralRent.owner()

            console.log("owner ... ", owner.address, own)

            // expect(await GeneralRent.owner()).to.equal(owner.address);
        });
    });

    describe('verifyRentSignature', function () {
        it('should verifyRentSignature successful', async function () {
            const { GeneralRent, owner} = await deployFixture();

            //fetch sign info from the third api by owner.address
            //todo get backend api to check it.

            const bl = await GeneralRent.connect(owner).verifyRentSignature('66cef4ca7180632953fff272', 1, 1724839414, '0x8fcb67b7129afbed6b359a069f424d7d2f6914de99dc5347faf98321c71c38f43c038c8bdc5bb0d156c0e0b1c2210474d6953c8d564d664702bf8b36512bad761c');
            expect(bl).to.equal(false);
        });
    });

    describe('startRent', function () {
        it('should startRent successful', async function () {
            const {owner,approveAmount, GeneralRent, RentToken} = await deployFixture();
            const bitmapExchangeRate = BigInt("10000000000000000000000"); //1e22 1w
            const generalRentAddress = await GeneralRent.getAddress();
            const n = 1;

            console.log('req = ', owner.address, generalRentAddress, n);

            const res = await renterRequest(owner.address, '0x09C824554840Aed574A3eBe9394fD6e9B5fa6eA7', n);
            const data = res.data.data
            console.log('res.data = ', data);
            if (data !== 'undefined') {
                console.log('res data.id = ', data.id, data.props_contract, data.locked_expiration, data.signature);
            }
            // return;


            await GeneralRent.connect(owner).startRent(data.id, data.props_contract, data.locked_expiration, data.signature);
            const rent = await GeneralRent.connect(owner).rentIdToRent(data.id);
            const rentDeposit = BigInt(rent[4]);
            const stopped = rent[6];

            console.log('rent = ', rent, rentDeposit, stopped)

            expect(rentDeposit).to.equal(BigInt(n)*BigInt(n)*BigInt(2)*bitmapExchangeRate)
            expect(stopped).to.equal(false);
        });
    });

    return;

    describe('startRent 2', function () {
        it('check owner balance change.', async function () {
            const {owner, GeneralRent, RentToken} = await deployFixture();

            const beforeBalance = await RentToken.connect(owner).balanceOf(owner.address);
            await GeneralRent.connect(owner).startRent('66af794c4f6194c815a5a6ab', 282, 2, 1722776184, '0x159af789be63a2a9437dfdc8225ed5e268dca703df8d9308765323c53a0937fc29cf166efd5a93180b6327df8748a5e12340f1cab7beb31155c4c524804f906200');
            const afterBalance = await RentToken.connect(owner).balanceOf(owner.address);

            const rent = await GeneralRent.connect(owner).rentIdToRent('66af794c4f6194c815a5a6ab');
            const rentDeposit = BigInt(rent[4]);

            expect(BigInt(beforeBalance) - BigInt(afterBalance)).to.equal(rentDeposit);

            const returned = await GeneralRent.connect(owner).getRentReturned('66af794c4f6194c815a5a6ab');
            expect(rentDeposit - BigInt(returned)).to.greaterThanOrEqual(0);
        });
    });

    describe('stopRent', function () {
        it('should startRent successful', async function () {
            const {owner,approveAmount, GeneralRent, RentToken} = await deployFixture();

            await GeneralRent.connect(owner).startRent('66af794c4f6194c815a5a6ab', 282, 2, 1722776184, '0x159af789be63a2a9437dfdc8225ed5e268dca703df8d9308765323c53a0937fc29cf166efd5a93180b6327df8748a5e12340f1cab7beb31155c4c524804f906200');
            await GeneralRent.connect(owner).stopRent('66af794c4f6194c815a5a6ab');

            const rent = await GeneralRent.connect(owner).rentIdToRent('66af794c4f6194c815a5a6ab');
            const stopped = rent[6];
            console.log('rent = ', rent, stopped)

            expect(stopped).to.equal(true);
        });
    });

    describe('stopRent 2', function () {
        it('check owner balance change.', async function () {
            const {owner, GeneralRent, RentToken} = await deployFixture();

            await GeneralRent.connect(owner).startRent('66af794c4f6194c815a5a6ab', 282, 2, 1722776184, '0x159af789be63a2a9437dfdc8225ed5e268dca703df8d9308765323c53a0937fc29cf166efd5a93180b6327df8748a5e12340f1cab7beb31155c4c524804f906200');

            const beforeBalance = await RentToken.connect(owner).balanceOf(owner.address);
            await GeneralRent.connect(owner).stopRent('66af794c4f6194c815a5a6ab');
            const afterBalance = await RentToken.connect(owner).balanceOf(owner.address);

            const rent = await GeneralRent.connect(owner).rentIdToRent('66af794c4f6194c815a5a6ab');
            const rentDeposit = BigInt(rent[4]);
            const returned = await GeneralRent.connect(owner).getRentReturned('66af794c4f6194c815a5a6ab');
            expect(rentDeposit - BigInt(returned)).to.greaterThan(0);

            expect(BigInt(afterBalance) - BigInt(beforeBalance)).to.equal(returned);

        });
    });

    describe('startRent && stopRent', function () {
        it('check daily rent rate successful', async function () {
            const {owner,approveAmount, GeneralRent, RentToken} = await deployFixture();

            let tx = await GeneralRent.connect(owner).startRent('66af794c4f6194c815a5a6ab', 282, 2, 1722776184, '0x159af789be63a2a9437dfdc8225ed5e268dca703df8d9308765323c53a0937fc29cf166efd5a93180b6327df8748a5e12340f1cab7beb31155c4c524804f906200');
            tx.wait();

            sleep(3000);

            tx = await GeneralRent.connect(owner).stopRent('66af794c4f6194c815a5a6ab');
            tx.wait()

            const rent = await GeneralRent.connect(owner).rentIdToRent('66af794c4f6194c815a5a6ab');
            console.log('rent = ', rent)

            const stopped = rent[6];
            expect(stopped).to.equal(true);

            //get rent reward
            const rentDeposit = BigInt(rent[4]);
            const returned = BigInt(rent[5])
            const rentReward = rentDeposit - returned;
            console.log('rentReward = ', rentReward)

            const startTime = BigInt(rent[7]);
            const endTime = BigInt(rent[8]);

            //cal rent reward
            const currentBaseRentFeeRate = await GeneralRent.connect(owner).currentBaseRentFeeRate();
            const currentDailyRentFeeRate = await GeneralRent.connect(owner).currentDailyRentFeeRate();
            const FEE_RATE_SCALE_FACTOR = await GeneralRent.connect(owner).FEE_RATE_SCALE_FACTOR();
            const SECONDS_PER_DAY = await GeneralRent.connect(owner).SECONDS_PER_DAY();

            const reward = rentDeposit * currentBaseRentFeeRate / FEE_RATE_SCALE_FACTOR +
                rentDeposit * currentDailyRentFeeRate * (endTime-startTime) / FEE_RATE_SCALE_FACTOR / SECONDS_PER_DAY;
            console.log('reward = ', reward)

            expect(reward).to.equal(rentReward);
        });
    });


    describe('startRent && stopRent 2', function () {
        it('check daily rent rate successful in multi change', async function () {
            const {owner,approveAmount, GeneralRent, RentToken} = await deployFixture();

            let tx = await GeneralRent.connect(owner).startRent('66af794c4f6194c815a5a6ab', 282, 2, 1722776184, '0x159af789be63a2a9437dfdc8225ed5e268dca703df8d9308765323c53a0937fc29cf166efd5a93180b6327df8748a5e12340f1cab7beb31155c4c524804f906200');
            tx.wait();

            sleep(3000);

            const _baseRentFeeRate2 = 10;
            const _dailyRentFeeRate2 = 10;
            tx = await GeneralRent.connect(owner).updateRentFeeRate(_baseRentFeeRate2, _dailyRentFeeRate2);
            tx.wait()

            sleep(3000);

            tx = await GeneralRent.connect(owner).stopRent('66af794c4f6194c815a5a6ab');
            tx.wait()

            const rent = await GeneralRent.connect(owner).rentIdToRent('66af794c4f6194c815a5a6ab');
            console.log('rent = ', rent)

            const stopped = rent[6];
            expect(stopped).to.equal(true);

            //get rent reward
            const rentDeposit = BigInt(rent[4]);
            const returned = BigInt(rent[5])
            const rentReward = rentDeposit - returned;
            console.log('rentReward = ', rentReward)

            const startTime = BigInt(rent[7]);
            const endTime = BigInt(rent[8]);

            //cal rent reward
            const FEE_RATE_SCALE_FACTOR = await GeneralRent.connect(owner).FEE_RATE_SCALE_FACTOR();
            const SECONDS_PER_DAY = await GeneralRent.connect(owner).SECONDS_PER_DAY();
            const rentFeeRateChangeHistory0 = await GeneralRent.connect(owner).rentFeeRateChangeHistory(0);
            const rentFeeRateChangeHistory1 = await GeneralRent.connect(owner).rentFeeRateChangeHistory(1);
            console.log('rentFeeRateChangeHistory0 = ', rentFeeRateChangeHistory0)
            console.log('rentFeeRateChangeHistory1 = ', rentFeeRateChangeHistory1)

            const reward0 = rentDeposit * rentFeeRateChangeHistory0[2] / FEE_RATE_SCALE_FACTOR +
                rentDeposit * rentFeeRateChangeHistory0[3] * (rentFeeRateChangeHistory0[1]-startTime) / FEE_RATE_SCALE_FACTOR / SECONDS_PER_DAY;
            const reward1 =
                rentDeposit * rentFeeRateChangeHistory1[3] * (endTime-rentFeeRateChangeHistory1[0]) / FEE_RATE_SCALE_FACTOR / SECONDS_PER_DAY;
            console.log('reward = ', reward0+reward1)

            expect(reward0+reward1).to.equal(rentReward);
        });
    });


    describe('updateMaxN', function () {
        it('should updateMaxN successful', async function () {
            const {GeneralRent, RentToken, owner} = await deployFixture();
            const _n = 5;

            await GeneralRent.connect(owner).updateMaxN(_n);
            const maxN = await GeneralRent.connect(owner).maxN();
            expect(maxN).to.equal(_n);
        });
    });

    describe('updateWithdrawer', function () {
        it('should updateWithdrawer successful', async function () {
            const {GeneralRent, RentToken, owner, addr1} = await deployFixture();

            await GeneralRent.connect(owner).updateWithdrawer(addr1.address);
            const withdrawer = await GeneralRent.connect(owner).withdrawer();
            expect(withdrawer).to.equal(addr1.address);
        });
    });

    describe('updateRentFeeRate', function () {
        it('should updateRentFeeRate successful', async function () {
            const {GeneralRent, RentToken, owner, addr1} = await deployFixture();
            const _baseRentFeeRate = 10;
            const _dailyRentFeeRate = 10;

            await GeneralRent.connect(owner).updateRentFeeRate(_baseRentFeeRate, _dailyRentFeeRate);
            const currentBaseRentFeeRate = await GeneralRent.connect(owner).currentBaseRentFeeRate();
            const currentDailyRentFeeRate = await GeneralRent.connect(owner).currentDailyRentFeeRate();
            expect(currentBaseRentFeeRate).to.equal(_baseRentFeeRate);
            expect(currentDailyRentFeeRate).to.equal(_dailyRentFeeRate);
        });
    });

    describe('stake interface', function () {
        it('check stake interface', async function () {
            const {GeneralRent, RentToken, owner} = await deployFixture();

            // await GeneralRent.connect(owner).withdrawReward(100);
            //'only stake contract allowed'
            // todo

            const rewardToken = await GeneralRent.connect(owner).getRewardToken();
            const rentToken = await GeneralRent.connect(owner).rentToken();
            console.log('rewardToken = ', rewardToken);
            console.log('rentToken = ', rentToken);
            expect(rewardToken).to.equal(rentToken);
        });
    });
})
