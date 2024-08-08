// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BitmapRent is OwnableUpgradeable {
    string public constant version = "1.0.0";
    uint256 public constant BITMAP_TOKEN_DECIMALS = 1e18;
    uint256 public constant BITMAP_EXCHANGE_RATE = 1e4;
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

    uint256 public maxN;
    address public bitmapToken;
    address public withdrawer;
    address public signer;

    struct RentStat {
        uint256 totalRentDeposit;
        uint256 totalRentFee;
        uint256 updateTimestamp; // the last time totalRentDeposit and totalRentFee changed

        uint256 totalWithdrawnRentFee; //total rent fee has been withdrawn by the stakeContract
    }

    RentStat public rentStat;

    struct Rent {
        string id;
        uint256 firstBitmap;
        uint256 n;
        address renter;
        uint256 deposit;
        uint256 rentFee;
        uint256 returned;
        uint256 liquidated;
        bool stopped;
        uint256 stoppedState; // StoppedState( 0.none 1.liquidate 2.abnormal liquidate, excessive rent fee )
        uint256 startTimestamp;
        uint256 stopTimestamp;
    }

    mapping(address => string[]) public renterToRentIds;
    mapping(string => Rent) public rentIdToRent;

    uint256 public currentBaseRentFeeRate; //unit: parts per million, example: 10000/1M = 1%
    uint256 public currentDailyRentFeeRate; //unit: parts per million

    struct RentFeeRateChange {
        uint256 beginTimestamp;
        uint256 endTimestamp;
        uint256 baseRentFeeRate;
        uint256 dailyRentFeeRate;
    }

    RentFeeRateChange[] public rentFeeRateChangeHistory;

    event UpdateMaxN(
        address msgSender,
        uint256 oldMaxN,
        uint256 maxN
    );

    event UpdateWithdrawer(
        address msgSender,
        address oldWithdrawer,
        address withdrawer);

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
        Rent rent
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
        address _bitmapToken,
        address _withdrawer,
        address _signer
    ) external
    onlyValidAddress(_initialOwner)
    onlyValidAddress(_bitmapToken)
    onlyValidAddress(_withdrawer)
    onlyValidAddress(_signer) initializer {
        bitmapToken = _bitmapToken;
        withdrawer = _withdrawer;
        signer = _signer;
        maxN = 20;

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
    function startRent(string memory _rentId, uint256 _firstBitmap, uint256 _n, uint256 _expiration, bytes calldata _signature) external whenNotPaused nonReentrant {
        require(_n > 0 && _n <= maxN, "invalid n");

        require(_expiration >= block.timestamp, "_signature expired");
        require(rentIdToRent[_rentId].deposit == 0, "_rentId already rented");

        //verify _signature
        require(verifyRentSignature(_rentId, _firstBitmap, _n, _expiration, _signature), "verify signature failed");

        //calc rent deposit
        uint256 rentDeposit = _n * _n * _n * BITMAP_EXCHANGE_RATE * BITMAP_TOKEN_DECIMALS;

        //receive bitmap token
        IERC20(bitmapToken).transferFrom(msg.sender, address(this), rentDeposit);

        //update stat
        _updateStartRentStat(rentDeposit);

        //build and save rent
        Rent memory rent = Rent(
            _rentId,
            _firstBitmap,
            _n,
            msg.sender,
            rentDeposit,
            0,
            false,
            block.timestamp,
            0
        );
        renterToRentIds[msg.sender].push(_rentId);
        rentIdToRent[_rentId] = rent;

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
    function stopRent(string memory _rentId) external whenNotPaused nonReentrant {
        require(!rentIdToRent[_rentId].stopped, "rent already terminated");
        require(rentIdToRent[_rentId].renter == msg.sender, "you are not renter");

        Rent storage rent = rentIdToRent[_rentId];

        //update stat
        _updateStopRentStat(rent.deposit);

        //update rent info
        rent.stopped = true;
        rent.stopTimestamp = block.timestamp;

        //return rent amount
        rent.rentFee = _calRentFee(rent);

        //excessive rent fee
        if (rent.rentFee > rent.deposit) {
            rent.stoppedState = StoppedState.AbnormalLiquidated;
            emit LiquidateRent(msg.sender, rent);
            return;
        }

        rent.returned = rent.deposit - rent.rentFee;

        IERC20(bitmapToken).transfer(msg.sender, rent.returned);

        emit StopRent(msg.sender, rent);
    }

    function liquidateRent(string memory _rentId) external whenNotPaused nonReentrant {
        require(!rentIdToRent[_rentId].stopped, "rent already terminated");

        Rent storage rent = rentIdToRent[_rentId];
        rent.stopped = true;
        rent.stopTimestamp = block.timestamp;

        //update stat
        _updateStopRentStat(rent.deposit);

        rent.rentFee = _calRentFee(rent);

        //excessive rent fee
        if (rent.rentFee > rent.deposit) {
            rent.stoppedState = StoppedState.AbnormalLiquidated;
            emit LiquidateRent(msg.sender, rent);
            return;
        }

        uint256 liquidated = rent.deposit - rent.rentFee;
        require(liquidated <= _dailyRentFee(rent.deposit), "It is not time for liquidation");

        //update rent info
        rent.stoppedState = StoppedState.Liquidated;
        rent.liquidated = liquidated;

        IERC20(bitmapToken).transfer(msg.sender, rent.liquidated);

        emit LiquidateRent(msg.sender, rent);
    }

    /**
    * @dev Get rent's returned bitmap token.
    *
    * - `_rentId`: the rent id when you rented n * n squares bitmaps.
    *
    * Firstly, we calculate the rent fee that have been generated,
    * And then, subtract the rent fee from the total amount.
    */
    function getRentReturned(string calldata _rentId) public view returns(uint256) {
        Rent memory rent = rentIdToRent[_rentId];
        if (rent.renter == address (0)) {
            return 0;
        }

        if (rent.stopped) {
            return rent.returned;
        }

        uint256 rentFee = _calRentFee(rent);
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
    function getRentsReturned(string[] calldata _rentIds) external view returns(uint256[] memory) {
        require(_rentIds.length > 0, "invalid _rentIds");

        uint256[] memory returnedList = new uint256[](_rentIds.length);
        for (uint16 i = 0; i < _rentIds.length; i++) {
            returnedList[i] = getRentReturned(_rentIds[i]);
        }

        return returnedList;
    }

    /**
    * @dev Signature verification function.
    * Calculate the hash with four parameters(_rentId, _firstBitmap, _n_expiration), and verify it.
    */
    function verifyRentSignature(string memory _rentId, uint256 _firstBitmap, uint256 _n, uint256 _expiration, bytes calldata _signature) public view returns (bool){
        bytes memory data = abi.encode(msg.sender, _rentId, _firstBitmap, _n, _expiration);
        bytes32 hash = keccak256(data);
        address receivedAddress = ECDSA.recover(hash, _signature);
        return receivedAddress != address(0) && receivedAddress == signer;
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

        IERC20(bitmapToken).transfer(withdrawer, _amount);

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
        return bitmapToken;
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
    function listRentsByRentIds(string[] calldata _rentIds) external view returns (Rent[] memory){
        require(_rentIds.length > 0, "invalid _rentIds");

        Rent[] memory rents = new Rent[](_rentIds.length);
        for (uint16 i = 0; i < _rentIds.length; i++) {
            string memory rentId = _rentIds[i];
            rents[i] = rentIdToRent[rentId];
        }

        return rents;
    }

    /**
    * @dev Batch check rents exists, by rent ids.
    */
    function batchCheckRentExists(string[] calldata _rentIds) external view returns (bool[] memory) {
        bool[] memory results = new bool[](_rentIds.length);
        for (uint16 i = 0; i < _rentIds.length; i++) {
            results[i] = rentIdToRent[_rentIds[i]].startTimestamp != 0;
        }
        return results;
    }

    /**
    * @dev Get the base rent info, contains bitmap price, and rental rate information.
    */
    function getRentBaseInfo() external view returns (uint256, uint256, uint256, uint256) {
        return (BITMAP_EXCHANGE_RATE, currentBaseRentFeeRate, currentDailyRentFeeRate, FEE_RATE_SCALE_FACTOR);
    }

    /**
    * @dev Update max N, the side length of n * n squares bitmaps.
    * (only by owner)
    */
    function updateMaxN(uint256 _n) external onlyOwner {
        require(_n > 0, "invalid _n");
        uint256 oldMaxN = maxN;
        maxN = _n;

        emit UpdateMaxN(msg.sender, oldMaxN, maxN);
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

    function _getUserValidRents(address user) internal view returns (Rent[] memory){
        if (renterToRentIds[user].length == 0) {
            return new Rent[](0);
        }

        uint16 count = 0;
        for (uint16 i = 0; i < renterToRentIds[user].length; i++) {
            string memory rentId = renterToRentIds[user][i];
            if (!rentIdToRent[rentId].stopped) {
                count += 1;
            }
        }

        Rent[] memory rents = new Rent[](count);
        uint16 next = 0;
        for (uint16 i = 0; i < renterToRentIds[user].length; i++) {
            string memory rentId = renterToRentIds[user][i];
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

