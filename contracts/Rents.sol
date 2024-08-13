// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Rents is OwnableUpgradeable {
    string public constant version = "1.0.0";
    uint256 public constant SECONDS_PER_DAY = 86400;
    uint256 public constant FEE_RATE_SCALE_FACTOR = 1e6;

    enum StoppedState {
        None,
        Liquidated,
        AbnormalLiquidated //excessive rent fee
    }

    address public pauseAdmin;
    bool public paused;
    uint256 private _nonReentrantStatus;

    address public rentToken;
    address public withdrawer;
    uint256 public oneGamePropsAmount;

    uint256 public id;

    struct RentStat {
        uint256 totalRentDeposit;
        uint256 totalRentFee;
        uint256 updateTimestamp; // the last time totalRentDeposit and totalRentFee changed

        uint256 totalWithdrawnRentFee; //total rent fee has been withdrawn by the stakeContract
    }

    RentStat public rentStat;

    struct Rent {
        uint256 id;
        address renter;
        uint256 deposit;
        uint256 rentFee;
        uint256 returned;
        uint256 liquidated;
        bool stopped;
        StoppedState stoppedState; // StoppedState( 0.none 1.liquidated 2.abnormal liquidated, excessive rent fee )
        uint256 startTimestamp;
        uint256 stopTimestamp;
    }

    mapping(address => uint256[]) public renterToRentIds;
    mapping(uint256 => Rent) public rentIdToRent;

    uint256 public currentBaseRentFeeRate; //unit: parts per million, example: 10000/1M = 1%
    uint256 public currentDailyRentFeeRate; //unit: parts per million

    struct RentFeeRateChange {
        uint256 beginTimestamp;
        uint256 endTimestamp;
        uint256 baseRentFeeRate;
        uint256 dailyRentFeeRate;
    }

    RentFeeRateChange[] public rentFeeRateChangeHistory;

    event UpdateWithdrawer(
        address msgSender,
        address oldWithdrawer,
        address withdrawer);

    event UpdateOneGamePropsAmount(
        address msgSender,
        uint256 oldAmount,
        uint256 newAmount);

    event UpdateRentFeeRate(
        address msgSender,
        uint256 oldBaseRentFeeRate,
        uint256 oldDailyRentFeeRate,
        uint256 currentBaseRentFeeRate,
        uint256 currentDailyRentFeeRate
    );

    event StartRent(
        address msgSender,
        Rent rent
    );

    event StopRent(
        address msgSender,
        Rent rent
    );

    event LiquidateRent(
        address msgSender,
        uint256 rentId,
        StoppedState stoppedState,
        uint256 liquidated,
        uint256 badDebts
    );

    event WithdrawReward(
        address msgSender,
        uint256 amount
    );

    event PauseAdminChanged(
        address adminSetter,
        address oldAddress,
        address newAddress
    );

    event PauseEvent(
        address pauseAdmin,
        bool paused
    );

    modifier onlyValidAddress(address addr) {
        require(addr != address(0), "Illegal address");
        _;
    }

    modifier nonReentrant() {
        require(_nonReentrantStatus == 0, "ReentrancyGuard: reentrant call");
        _nonReentrantStatus = 1;
        _;
        _nonReentrantStatus = 0;
    }

    /**
    * @dev Initialization function
    *
    * - `_initialOwner`：the initial owner is set to the address provided by the deployer. This can
    *      later be changed with {transferOwnership}.
    * - `_bitmapToken`: spend the bitmap token to rent the bitmaps.
    * - `_withdrawer`: the withdrawer is an external stake contract that can withdraw reward from this contract.
    * - `_signer`: the sign address when you want to rent the bitmaps.
    */
    function initialize(
        address _initialOwner,
        address _rentToken,
        address _withdrawer,
        uint256 _oneGamePropsAmount
    ) external
    onlyValidAddress(_initialOwner)
    onlyValidAddress(_rentToken)
    onlyValidAddress(_withdrawer) initializer {
        rentToken = _rentToken;
        withdrawer = _withdrawer;
        require(_oneGamePropsAmount > 0, "invalid _oneGamePropsAmount");
        oneGamePropsAmount = _oneGamePropsAmount;

        currentBaseRentFeeRate = 10000;
        currentDailyRentFeeRate = 100;
        _pushRentFeeRate();
        emit UpdateRentFeeRate(msg.sender, 0, 0, currentBaseRentFeeRate, currentDailyRentFeeRate);

        __Ownable_init_unchained(_initialOwner);
    }

    /**
    * @dev Start rent: start a rent that has been verified and signed by the centralized service.
    *
    * - `_rentId`: the rent id when you rent n * n squares bitmaps.
    * - `_firstBitmap`: the first bitmap of all that you rented, they are n * n * n squares bitmaps.
    * - `_n`: The side length of an n * n squares bitmaps.
    * - `_expiration`: the validity period of the signature, after the expiration time, you need to re-sign.
    * - `_signature`: the signature of this rent, signature result of the above four parameters.
    *
    * Firstly, we will verify the rent signature, signed by the centralized service. If signature is valid,
    * we transfer the specified amount of bitmapToken from sender to this contract.
    * and then, we update the global rent stat, such as totalRentFee,totalRentDeposit,updateTime,etc.
    * finally, we build a rent record and save it.
    */
    function startRent(uint256 _rentDeposit) external whenNotPaused nonReentrant {
        require(_rentDeposit > oneGamePropsAmount, "invalid _rentAmount");

        uint256 rentId = _id();

        //receive bitmap token
        IERC20(rentToken).transferFrom(msg.sender, address(this), _rentDeposit);

        //update stat
        _updateStartRentStat(_rentDeposit);

        //build and save rent
        Rent memory rent = Rent(
            rentId,
            msg.sender,
            _rentDeposit,
            0,
            0,
            0,
            false,
            StoppedState.None,
            block.timestamp,
            0
        );

        renterToRentIds[msg.sender].push(rentId);
        rentIdToRent[rentId] = rent;

        emit StartRent(msg.sender, rent);
    }

    /**
    * @dev Stop rent: stop the specified rent, and settlement for the total rent fee.
    *
    * - `_rentId`: the rent id when you rented n * n squares bitmaps.
    *
    * Firstly, we update the global rent stat, such as totalRentFee,totalRentDeposit,updateTime.
    * Then, transfers the remain bitmap token from this contract to the renter.
    */
    function stopRent(uint256 _rentId) external whenNotPaused nonReentrant {
        require(!rentIdToRent[_rentId].stopped, "rent already terminated");
        require(rentIdToRent[_rentId].renter == msg.sender, "you are not renter");

        Rent storage rent = rentIdToRent[_rentId];

        //update stat
        _updateStopRentStat(rent.deposit);

        //update rent info
        rent.stopped = true;
        rent.stopTimestamp = block.timestamp;
        rent.rentFee = _calRentFee(rent);
        require(rent.deposit >= rent.rentFee, "excessive rent fee, can't stop");

        rent.returned = rent.deposit - rent.rentFee;

        if (rent.returned > 0) {
            IERC20(rentToken).transfer(msg.sender, rent.returned);
        }

        emit StopRent(msg.sender, rent);
    }

    function liquidateRent(uint256 _rentId) external whenNotPaused nonReentrant {
        require(!rentIdToRent[_rentId].stopped, "rent already terminated");

        Rent storage rent = rentIdToRent[_rentId];

        //update stat
        _updateStopRentStat(rent.deposit);

        rent.stopped = true;
        rent.stopTimestamp = block.timestamp;
        rent.rentFee = _calRentFee(rent);

        //excessive rent fee
        if (rent.rentFee > rent.deposit) {
            rent.stoppedState = StoppedState.AbnormalLiquidated;
            uint256 badDebts = rent.rentFee-rent.deposit;

            //liquidate: repay bad debts
            IERC20(rentToken).transferFrom(msg.sender, address (this), badDebts);

            emit LiquidateRent(msg.sender, _rentId, StoppedState.AbnormalLiquidated, 0, badDebts);
            return;
        }

        uint256 liquidated = rent.deposit - rent.rentFee;
        require(liquidated <= _dailyRentFee(rent.deposit), "It is not time for liquidation");

        //update rent info
        rent.stoppedState = StoppedState.Liquidated;
        rent.liquidated = liquidated;

        //liquidate: get benefits
        if (rent.liquidated > 0) { //new
            IERC20(rentToken).transfer(msg.sender, rent.liquidated);
        }

        emit LiquidateRent(msg.sender, _rentId, StoppedState.Liquidated, rent.liquidated, 0);
    }

    /**
    * @dev Get rent's returned bitmap token.
    *
    * - `_rentId`: the rent id when you rented n * n squares bitmaps.
    *
    * Firstly, we calculate the rent fee that have been generated,
    * And then, subtract the rent fee from the total amount.
    */
    function getRentReturned(uint256 _rentId) public view returns(uint256) {
        Rent memory rent = rentIdToRent[_rentId];
        if (rent.renter == address (0)) {
            return 0;
        }

        if (rent.stopped) {
            return rent.returned;
        }

        uint256 rentFee = _calRentFee(rent);
        if (rentFee > rent.deposit) { //new
            return 0;
        }
        return rent.deposit - rentFee;
    }

    /**
    * @dev Get rents' returnedList bitmap token.
    *
    * - `_rentIds`: the rent id list when these are rented n * n squares bitmaps.
    *
    * Firstly, we calculate the rent fee that have been generated,
    * And then, subtract the rent fee from the total amount.
    */
    function getRentsReturned(uint256[] calldata _rentIds) external view returns(uint256[] memory) {
        require(_rentIds.length > 0, "invalid _rentIds");

        uint256[] memory returnedList = new uint256[](_rentIds.length);
        for (uint16 i = 0; i < _rentIds.length; i++) {
            returnedList[i] = getRentReturned(_rentIds[i]);
        }

        return returnedList;
    }

    /**
    * @dev Withdraw reward by the external stake contract, Pick up address, must be specified stake contract address.
    * (external interface function)
    *
    * - `_amount`: withdraw amount bitmap token.
    */
    function withdrawReward(uint256 _amount) external whenNotPaused nonReentrant {
        require(_amount > 0, "invalid _amount");
        require(msg.sender == withdrawer, "only stake contract allowed");

        _updateRentStat();
        require(rentStat.totalWithdrawnRentFee + _amount <= rentStat.totalRentFee, "amount exceed");
        rentStat.totalWithdrawnRentFee += _amount;

        IERC20(rentToken).transfer(withdrawer, _amount);

        emit WithdrawReward(msg.sender, _amount);
    }

    /**
    * @dev Get total reward by the external stake contract.
    * (external interface function)
    */
    function getTotalReward() public view returns (uint256) {
        uint256 interval = block.timestamp - rentStat.updateTimestamp;
        uint256 feePerSecond = rentStat.totalRentDeposit * currentDailyRentFeeRate / FEE_RATE_SCALE_FACTOR / SECONDS_PER_DAY;
        return rentStat.totalRentFee + feePerSecond * interval;
    }

    /**
    * @dev Get reward token by the external stake contract.
    * (external interface function)
    */
    function getRewardToken() external view returns (address) {
        return rentToken;
    }

    /**
    * @dev List the specified user's rents.
    *
    * - `_user`: the specified user.
    * - `_all`: if true, list all rents; if false, list valid rents.
    */
    function listUserRents(address _user, bool _all) external view returns (Rent[] memory){
        if (_all) {
            return _getUserAllRents(_user);
        }

        return _getUserValidRents(_user);
    }

    /**
    * @dev List the rents by rent ids.
    */
    function listRentsByRentIds(uint256[] calldata _rentIds) external view returns (Rent[] memory){
        require(_rentIds.length > 0, "invalid _rentIds");

        Rent[] memory rents = new Rent[](_rentIds.length);
        for (uint16 i = 0; i < _rentIds.length; i++) {
            uint256 rentId = _rentIds[i];
            rents[i] = rentIdToRent[rentId];
        }

        return rents;
    }

    /**
    * @dev Batch check rents exists, by rent ids.
    */
    function batchCheckRentExists(uint256[] calldata _rentIds) external view returns (bool[] memory) {
        bool[] memory results = new bool[](_rentIds.length);
        for (uint16 i = 0; i < _rentIds.length; i++) {
            results[i] = rentIdToRent[_rentIds[i]].startTimestamp != 0 && !rentIdToRent[_rentIds[i]].stopped; //new
        }
        return results;
    }

    /**
    * @dev Get the base rent info, contains bitmap price, and rental rate information.
    */
    function getRentBaseInfo() external view returns (uint256, uint256, uint256, uint256) {
        return (oneGamePropsAmount, currentBaseRentFeeRate, currentDailyRentFeeRate, FEE_RATE_SCALE_FACTOR);
    }

    /**
    * @dev Update the withdrawer that is the external stake contract.
    * (only by owner)
    */
    function updateWithdrawer(address _withdrawer) external onlyOwner {
        require(_withdrawer != address(0), "invalid _withdrawer");
        address oldWithdrawer = withdrawer;
        withdrawer = _withdrawer;

        emit UpdateWithdrawer(msg.sender, oldWithdrawer, withdrawer);
    }

    function updateOneGamePropsAmount(uint256 _amount) external onlyOwner {
        require(_amount > 0, "invalid _amount");
        uint256 oldAmount = oneGamePropsAmount;
        oneGamePropsAmount = _amount;

        emit UpdateOneGamePropsAmount(msg.sender, oldAmount, _amount);
    }

    /**
    * @dev Update rent fee rate.
    * (only by owner)
    *
    * - `_baseRentFeeRate`: the base rent fee rate, directly spend this rate amount at the start of the rent.
    * - `_dailyRentFeeRate`: the daily rent fee rate, spend this rate amount every day.
    *
    * Push it in rentFeeRateHistory. when someone want to stop rent, it can be used to calculate rent fee
    * and return amount.
    */
    function updateRentFeeRate(uint256 _baseRentFeeRate, uint256 _dailyRentFeeRate) external onlyOwner {
        require(_baseRentFeeRate > 0, "invalid _baseRentFeeRate");
        require(_dailyRentFeeRate > 0, "invalid _dailyRentFeeRate");

        uint256 oldBaseRentFeeRate = currentBaseRentFeeRate;
        uint256 oldDailyRentFeeRate = currentDailyRentFeeRate;

        _updateRentStat();

        currentBaseRentFeeRate = _baseRentFeeRate;
        currentDailyRentFeeRate = _dailyRentFeeRate;

        _pushRentFeeRate();

        emit UpdateRentFeeRate(
            msg.sender,
            oldBaseRentFeeRate,
            oldDailyRentFeeRate,
            currentBaseRentFeeRate,
            currentDailyRentFeeRate);
    }

    function _pushRentFeeRate() internal {
        if (rentFeeRateChangeHistory.length > 0) {
            rentFeeRateChangeHistory[rentFeeRateChangeHistory.length - 1].endTimestamp = block.timestamp;
        }

        RentFeeRateChange memory rentFeeRate = RentFeeRateChange(
            block.timestamp,
            0,
            currentBaseRentFeeRate,
            currentDailyRentFeeRate);

        rentFeeRateChangeHistory.push(rentFeeRate);
    }

    /**
    * @dev Get all rent fee changed history.
    */
    function getRentFeeChangeHistory() external view returns (RentFeeRateChange[] memory){
        return rentFeeRateChangeHistory;
    }

    function _id() internal returns(uint256){
        id += 1;
        return id;
    }

    function _getUserValidRents(address user) internal view returns (Rent[] memory){
        if (renterToRentIds[user].length == 0) {
            return new Rent[](0);
        }

        uint16 count = 0;
        for (uint16 i = 0; i < renterToRentIds[user].length; i++) {
            uint256 rentId = renterToRentIds[user][i];
            if (!rentIdToRent[rentId].stopped) {
                count += 1;
            }
        }

        Rent[] memory rents = new Rent[](count);
        uint16 next = 0;
        for (uint16 i = 0; i < renterToRentIds[user].length; i++) {
            uint256 rentId = renterToRentIds[user][i];
            if (!rentIdToRent[rentId].stopped) {
                rents[next] = rentIdToRent[rentId];
                next += 1;
            }
        }

        return rents;
    }

    function _getUserAllRents(address user) internal view returns (Rent[] memory){
        if (renterToRentIds[user].length == 0) {
            return new Rent[](0);
        }

        Rent[] memory rents = new Rent[](renterToRentIds[user].length);
        for (uint16 i = 0; i < renterToRentIds[user].length; i++) {
            rents[i] = rentIdToRent[renterToRentIds[user][i]];
        }

        return rents;
    }

    function _updateStartRentStat(uint256 rentAmount) internal {
        //Firstly update totalRentFee, then totalRentDeposit, finally updateTime.
        uint256 interval = block.timestamp - rentStat.updateTimestamp;
        uint256 feePerSecond = _rentFeePerSecond(rentStat.totalRentDeposit);
        uint256 baseRentFee = _baseRentFee(rentAmount);

        rentStat.totalRentFee += feePerSecond * interval + baseRentFee;
        rentStat.totalRentDeposit += rentAmount;
        rentStat.updateTimestamp = block.timestamp;
    }

    function _updateStopRentStat(uint256 rentAmount) internal {
        //firstly update totalRentFee, then totalRentDeposit, finally updateTime.
        uint256 interval = block.timestamp - rentStat.updateTimestamp;
        uint256 feePerSecond = _rentFeePerSecond(rentStat.totalRentDeposit);

        rentStat.totalRentFee += feePerSecond * interval;
        rentStat.totalRentDeposit -= rentAmount;
        rentStat.updateTimestamp = block.timestamp;
    }

    function _updateRentStat() internal {
        //Firstly update totalRentFee, finally updateTime.
        uint256 interval = block.timestamp - rentStat.updateTimestamp;
        uint256 feePerSecond = _rentFeePerSecond(rentStat.totalRentDeposit);

        rentStat.totalRentFee += feePerSecond * interval;
        rentStat.updateTimestamp = block.timestamp;
    }

    function _rentFeePerSecond(uint256 rentAmount) internal view returns (uint256) {
        return rentAmount * currentDailyRentFeeRate / FEE_RATE_SCALE_FACTOR / SECONDS_PER_DAY;
    }

    function _baseRentFee(uint256 rentAmount) internal view returns (uint256) {
        return rentAmount * currentBaseRentFeeRate / FEE_RATE_SCALE_FACTOR;
    }

    function _dailyRentFee(uint256 rentAmount) internal view returns (uint256) {
        return rentAmount * currentDailyRentFeeRate / FEE_RATE_SCALE_FACTOR;
    }

    function _calRentFee(Rent memory rentInfo) internal view returns (uint256) {
        uint256 rentFee = 0;

        uint16 i = 0;
        for (; i < rentFeeRateChangeHistory.length; i++) {
            if (rentFeeRateChangeHistory[i].endTimestamp == 0 || rentInfo.startTimestamp < rentFeeRateChangeHistory[i].endTimestamp) {
                uint256 baseRentFee = _baseRentFeeExt(rentInfo.deposit, rentFeeRateChangeHistory[i].baseRentFeeRate);
                uint256 feePerSecond = _rentFeePerSecondExt(rentInfo.deposit, rentFeeRateChangeHistory[i].dailyRentFeeRate);
                uint256 begin = rentInfo.startTimestamp;
                uint256 end = rentFeeRateChangeHistory[i].endTimestamp;
                if (end == 0) {
                    end = block.timestamp;
                }
                rentFee += baseRentFee + feePerSecond * (end - begin);
                break;
            }
        }

        i += 1;

        for (; i < rentFeeRateChangeHistory.length; i++) {
            uint256 begin = rentFeeRateChangeHistory[i].beginTimestamp;
            uint256 end = rentFeeRateChangeHistory[i].endTimestamp;
            if (end == 0) {
                end = block.timestamp;
            }
            uint256 feePerSecond = _rentFeePerSecondExt(rentInfo.deposit, rentFeeRateChangeHistory[i].dailyRentFeeRate);
            rentFee += feePerSecond * (end - begin);
        }

        return rentFee;
    }

    function _rentFeePerSecondExt(uint256 rentAmount, uint256 _dailyRentFeeRate) internal pure returns (uint256) {
        return rentAmount * _dailyRentFeeRate / FEE_RATE_SCALE_FACTOR / SECONDS_PER_DAY;
    }

    function _baseRentFeeExt(uint256 rentAmount, uint256 _baseRentFeeRate) internal pure returns (uint256) {
        return rentAmount * _baseRentFeeRate / FEE_RATE_SCALE_FACTOR;
    }

    //Pause ...
    function setPauseAdmin(address _account) public onlyOwner {
        require(_account != address (0), "invalid _account");
        address oldPauseAdmin = pauseAdmin;
        pauseAdmin = _account;
        emit PauseAdminChanged(msg.sender, oldPauseAdmin, pauseAdmin);
    }

    modifier whenNotPaused() {
        require(!paused, "pause is on");
        _;
    }

    /**
    * @dev Pause the activity, only by pauseAdmin.
    */
    function pause() public whenNotPaused {
        require(msg.sender == pauseAdmin, "Illegal pause permissions");
        paused = true;
        emit PauseEvent(msg.sender, paused);
    }

    /**
    * @dev Unpause the activity, only by owner.
    */
    function unpause() public onlyOwner {
        paused = false;
        emit PauseEvent(msg.sender, paused);
    }
}