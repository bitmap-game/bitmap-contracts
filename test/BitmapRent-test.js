const { expect} = require('chai');
const { ethers } = require("hardhat");
const {sleep} = require("@nomicfoundation/hardhat-verify/internal/utilities");
const {bigint} = require("hardhat/internal/core/params/argumentTypes");
const {address} = require("hardhat/internal/core/config/config-validation");

describe("Test BitmapRent Contract", function () {
    async function deployFixture() {
        const erc20CapAmount = BigInt("1000000000000000000000000000"); // 1e27 1G
        const approveAmount = BigInt("1000000000000000000000000"); //1e24 1M
        const bitmapSignAddress = "0xA017e1D6594dBD6b849F1911632e95ca59b41090"
        const merlStakeAddress = "0x0000000000000000000000000000000000000000"

        //owner
        let [owner, addr1] = await ethers.getSigners();

        //bitmapToken
        const ERC20TokenWrapped = await ethers.getContractFactory("ERC20TokenWrapped", owner);
        const BitmapToken = await ERC20TokenWrapped.deploy("bitmapToken", "bitmapToken", 18, erc20CapAmount);

        //BitmapRent
        const BitmapRentContract = await ethers.getContractFactory("BitmapRent", owner);
        const BitmapRent = await BitmapRentContract.deploy();
        await BitmapRent.initialize(owner, BitmapToken.getAddress(), merlStakeAddress, bitmapSignAddress);

        //approve
        await BitmapToken.connect(owner).approve(BitmapRent, approveAmount);
        await BitmapToken.connect(owner).mint(owner, approveAmount);

        return {owner, addr1, approveAmount, BitmapRent, BitmapToken};
    }

    describe('deployment', function () {
        it('should set the right owner', async function () {
            const {BitmapRent, owner} = await deployFixture();
            expect(await BitmapRent.owner()).to.equal(owner.address);
        });
    });

    return;
    describe('verifyRentSignature', function () {
        it('should verifyRentSignature successful', async function () {
            const { BitmapRent, owner} = await deployFixture();

            //fetch sign info from the third api by owner.address
            //todo get backend api to check it.

            const bl = await BitmapRent.connect(owner).verifyRentSignature('66b232a5732146219e896a53', 290, 2, 1722954705, '0xa8893d97980a41a2cb31fd4673ec75faee6e71b01cd17c9a2bc329f524523f635ca232fe4cb50dcf1c4a8c7c9f64621ce5e9c72fedca5ef053e3af10b9487b1f01');
            expect(bl).to.equal(false);
        });
    });

    describe('startRent', function () {
        it('should startRent successful', async function () {
            const {owner,approveAmount, BitmapRent, BitmapToken} = await deployFixture();
            const bitmapExchangeRate = BigInt("10000000000000000000000"); //1e22 1w
            const n = 2;

            await BitmapRent.connect(owner).startRent('66af794c4f6194c815a5a6ab', 282, n, 1722776184, '0x159af789be63a2a9437dfdc8225ed5e268dca703df8d9308765323c53a0937fc29cf166efd5a93180b6327df8748a5e12340f1cab7beb31155c4c524804f906200');

            const rent = await BitmapRent.connect(owner).rentIdToRent('66af794c4f6194c815a5a6ab');
            const rentDeposit = BigInt(rent[4]);
            const stopped = rent[6];
            console.log('rent = ', rent, rentDeposit, stopped)

            expect(rentDeposit).to.equal(BigInt(n)*BigInt(n)*BigInt(2)*bitmapExchangeRate)
            expect(stopped).to.equal(false);
        });
    });

    describe('startRent 2', function () {
        it('check owner balance change.', async function () {
            const {owner, BitmapRent, BitmapToken} = await deployFixture();

            const beforeBalance = await BitmapToken.connect(owner).balanceOf(owner.address);
            await BitmapRent.connect(owner).startRent('66af794c4f6194c815a5a6ab', 282, 2, 1722776184, '0x159af789be63a2a9437dfdc8225ed5e268dca703df8d9308765323c53a0937fc29cf166efd5a93180b6327df8748a5e12340f1cab7beb31155c4c524804f906200');
            const afterBalance = await BitmapToken.connect(owner).balanceOf(owner.address);

            const rent = await BitmapRent.connect(owner).rentIdToRent('66af794c4f6194c815a5a6ab');
            const rentDeposit = BigInt(rent[4]);

            expect(BigInt(beforeBalance) - BigInt(afterBalance)).to.equal(rentDeposit);

            const returned = await BitmapRent.connect(owner).getRentReturned('66af794c4f6194c815a5a6ab');
            expect(rentDeposit - BigInt(returned)).to.greaterThanOrEqual(0);
        });
    });

    describe('stopRent', function () {
        it('should startRent successful', async function () {
            const {owner,approveAmount, BitmapRent, BitmapToken} = await deployFixture();

            await BitmapRent.connect(owner).startRent('66af794c4f6194c815a5a6ab', 282, 2, 1722776184, '0x159af789be63a2a9437dfdc8225ed5e268dca703df8d9308765323c53a0937fc29cf166efd5a93180b6327df8748a5e12340f1cab7beb31155c4c524804f906200');
            await BitmapRent.connect(owner).stopRent('66af794c4f6194c815a5a6ab');

            const rent = await BitmapRent.connect(owner).rentIdToRent('66af794c4f6194c815a5a6ab');
            const stopped = rent[6];
            console.log('rent = ', rent, stopped)

            expect(stopped).to.equal(true);
        });
    });

    describe('stopRent 2', function () {
        it('check owner balance change.', async function () {
            const {owner, BitmapRent, BitmapToken} = await deployFixture();

            await BitmapRent.connect(owner).startRent('66af794c4f6194c815a5a6ab', 282, 2, 1722776184, '0x159af789be63a2a9437dfdc8225ed5e268dca703df8d9308765323c53a0937fc29cf166efd5a93180b6327df8748a5e12340f1cab7beb31155c4c524804f906200');

            const beforeBalance = await BitmapToken.connect(owner).balanceOf(owner.address);
            await BitmapRent.connect(owner).stopRent('66af794c4f6194c815a5a6ab');
            const afterBalance = await BitmapToken.connect(owner).balanceOf(owner.address);

            const rent = await BitmapRent.connect(owner).rentIdToRent('66af794c4f6194c815a5a6ab');
            const rentDeposit = BigInt(rent[4]);
            const returned = await BitmapRent.connect(owner).getRentReturned('66af794c4f6194c815a5a6ab');
            expect(rentDeposit - BigInt(returned)).to.greaterThan(0);

            expect(BigInt(afterBalance) - BigInt(beforeBalance)).to.equal(returned);

        });
    });

    describe('startRent && stopRent', function () {
        it('check daily rent rate successful', async function () {
            const {owner,approveAmount, BitmapRent, BitmapToken} = await deployFixture();

            let tx = await BitmapRent.connect(owner).startRent('66af794c4f6194c815a5a6ab', 282, 2, 1722776184, '0x159af789be63a2a9437dfdc8225ed5e268dca703df8d9308765323c53a0937fc29cf166efd5a93180b6327df8748a5e12340f1cab7beb31155c4c524804f906200');
            tx.wait();

            sleep(3000);

            tx = await BitmapRent.connect(owner).stopRent('66af794c4f6194c815a5a6ab');
            tx.wait()

            const rent = await BitmapRent.connect(owner).rentIdToRent('66af794c4f6194c815a5a6ab');
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
            const currentBaseRentFeeRate = await BitmapRent.connect(owner).currentBaseRentFeeRate();
            const currentDailyRentFeeRate = await BitmapRent.connect(owner).currentDailyRentFeeRate();
            const FEE_RATE_SCALE_FACTOR = await BitmapRent.connect(owner).FEE_RATE_SCALE_FACTOR();
            const SECONDS_PER_DAY = await BitmapRent.connect(owner).SECONDS_PER_DAY();

            const reward = rentDeposit * currentBaseRentFeeRate / FEE_RATE_SCALE_FACTOR +
                rentDeposit * currentDailyRentFeeRate * (endTime-startTime) / FEE_RATE_SCALE_FACTOR / SECONDS_PER_DAY;
            console.log('reward = ', reward)

            expect(reward).to.equal(rentReward);
        });
    });


    describe('startRent && stopRent 2', function () {
        it('check daily rent rate successful in multi change', async function () {
            const {owner,approveAmount, BitmapRent, BitmapToken} = await deployFixture();

            let tx = await BitmapRent.connect(owner).startRent('66af794c4f6194c815a5a6ab', 282, 2, 1722776184, '0x159af789be63a2a9437dfdc8225ed5e268dca703df8d9308765323c53a0937fc29cf166efd5a93180b6327df8748a5e12340f1cab7beb31155c4c524804f906200');
            tx.wait();

            sleep(3000);

            const _baseRentFeeRate2 = 10;
            const _dailyRentFeeRate2 = 10;
            tx = await BitmapRent.connect(owner).updateRentFeeRate(_baseRentFeeRate2, _dailyRentFeeRate2);
            tx.wait()

            sleep(3000);

            tx = await BitmapRent.connect(owner).stopRent('66af794c4f6194c815a5a6ab');
            tx.wait()

            const rent = await BitmapRent.connect(owner).rentIdToRent('66af794c4f6194c815a5a6ab');
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
            const FEE_RATE_SCALE_FACTOR = await BitmapRent.connect(owner).FEE_RATE_SCALE_FACTOR();
            const SECONDS_PER_DAY = await BitmapRent.connect(owner).SECONDS_PER_DAY();
            const rentFeeRateChangeHistory0 = await BitmapRent.connect(owner).rentFeeRateChangeHistory(0);
            const rentFeeRateChangeHistory1 = await BitmapRent.connect(owner).rentFeeRateChangeHistory(1);
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
            const {BitmapRent, BitmapToken, owner} = await deployFixture();
            const _n = 5;

            await BitmapRent.connect(owner).updateMaxN(_n);
            const maxN = await BitmapRent.connect(owner).maxN();
            expect(maxN).to.equal(_n);
        });
    });

    describe('updateWithdrawer', function () {
        it('should updateWithdrawer successful', async function () {
            const {BitmapRent, BitmapToken, owner, addr1} = await deployFixture();

            await BitmapRent.connect(owner).updateWithdrawer(addr1.address);
            const withdrawer = await BitmapRent.connect(owner).withdrawer();
            expect(withdrawer).to.equal(addr1.address);
        });
    });

    describe('updateRentFeeRate', function () {
        it('should updateRentFeeRate successful', async function () {
            const {BitmapRent, BitmapToken, owner, addr1} = await deployFixture();
            const _baseRentFeeRate = 10;
            const _dailyRentFeeRate = 10;

            await BitmapRent.connect(owner).updateRentFeeRate(_baseRentFeeRate, _dailyRentFeeRate);
            const currentBaseRentFeeRate = await BitmapRent.connect(owner).currentBaseRentFeeRate();
            const currentDailyRentFeeRate = await BitmapRent.connect(owner).currentDailyRentFeeRate();
            expect(currentBaseRentFeeRate).to.equal(_baseRentFeeRate);
            expect(currentDailyRentFeeRate).to.equal(_dailyRentFeeRate);
        });
    });

    describe('stake interface', function () {
        it('check stake interface', async function () {
            const {BitmapRent, BitmapToken, owner} = await deployFixture();

            // await BitmapRent.connect(owner).withdrawReward(100);
            //'only stake contract allowed'
            // todo

            const rewardToken = await BitmapRent.connect(owner).getRewardToken();
            const bitmapToken = await BitmapRent.connect(owner).bitmapToken();
            console.log('rewardToken = ', rewardToken);
            console.log('bitmapToken = ', bitmapToken);
            expect(rewardToken).to.equal(bitmapToken);
        });
    });
})
