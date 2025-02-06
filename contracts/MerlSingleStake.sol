// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IRewardContract.sol";

contract MerlSingleStake is OwnableUpgradeable {
    string public constant version = "1.0.0";
    uint256 public constant ONE_MERL = 1e18;
    uint256 public constant SCALE_FACTOR = 1e18;
    address public pauseAdmin;
    bool public paused;
    uint256 private _nonReentrantStatus;

    address public merlToken;
    address public rewardContract;

    uint256 totalMerl;
    struct GlobalReward {
        uint256 scaledTotalRewardsPerMerl;
        uint256 totalRewardsEarned;
        uint256 totalRewardsClaimed;

        uint256 updateTimestamp;
    }
    GlobalReward public globalReward;

    struct AccountReward {
        uint256 scaledSettledRewardPerMerl;
        uint256 settledRewardsEarned;
        uint256 settledTimestamp;
        uint256 rewardsClaimed;
    }
    struct Stake {
        address account;
        uint256 merl;

//        mapping(address => AccountReward) rewards;
        AccountReward rewards;

        bool unstaked;
        uint256 unstakedTime;

        uint256 updateTimestamp;
    }
    mapping(address => Stake) public accountToStake;

    event StakeMerl(
        address msgSender,
        uint256 amount
    );

    event UnstakeMerl(
        address msgSender,
        uint256 amount
    );

    event ClaimReward(
        address msgSender,
        address rewardContract,
        address rewardToken,
        uint256 amount,
        uint256 claimTimestamp
    );

    event PauseAdminChanged(
        address adminSetter,
        address oldAddress,
        address newAddress
    );

    event PauseEvent(
        address adminSetter,
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

    constructor() {
        _disableInitializers();
    }

    /**
    * @dev Initialization function
    *
    * - `_initialOwner`：the initial owner is set to the address provided by the deployer. This can
    *      later be changed with {transferOwnership}.
    * - `_merlToken`: stake merl token to get rewards.
    * - `_rewardContract`:the rewards contract address.
    */
    function initialize(
        address _initialOwner,
        address _merlToken,
        address _rewardContract
    ) external
    onlyValidAddress(_initialOwner)
    onlyValidAddress(_merlToken)
    onlyValidAddress(_rewardContract) initializer {
        merlToken = _merlToken;
        rewardContract = _rewardContract;

        // Initialize OZ contracts
        __Ownable_init_unchained(_initialOwner);
    }

    //new
    function stakeMerl(uint256 _amount) external whenNotPaused nonReentrant {
        require(_amount >= ONE_MERL, "at least 1 MERL");

        address staker = msg.sender;
        IERC20(merlToken).transferFrom(staker, address(this), _amount);

        _settleGlobalReward();
        totalMerl += _amount;

        if (accountToStake[staker].account == address(0)) {
            accountToStake[staker].account = staker;
            accountToStake[staker].updateTimestamp = block.timestamp;
        }
        _settleAccountReward(staker);
        accountToStake[staker].merl += _amount;

        emit StakeMerl(
            staker,
            _amount
        );
    }

    //new
    function unstakeMerl(uint256 _amount) external whenNotPaused nonReentrant {
        require(_amount > 0, "invalid _amount");
        require(accountToStake[msg.sender].merl >= _amount, "Insufficient deposit");

        //必须是没有unstaked才能操作
        require(!accountToStake[staker].unstaked, "it is unstaking");

        //在claim时候判断时间，时间到了claim并且设置unstaked=false
        //require(accountToStake[staker].unstakedTime > 86400 * 7, "it is unstaking");

        address staker = msg.sender;

        _settleGlobalReward();
        totalMerl -= _amount;

        _settleAccountReward(staker);
        accountToStake[staker].merl -= _amount;
        accountToStake[staker].unstaked = true;
        accountToStake[staker].unstakedTime = time.Block;

        emit UnstakeMerl(
            staker,
            _amount
        );
    }

    //new
    function claimReward() external whenNotPaused nonReentrant {
        require(accountToStake[msg.sender].account != address (0), "invalid user");

        //必须是unstaked才能操作
        require(accountToStake[staker].unstaked, "it is not unstaking");

        //在claim时候判断时间，时间到了claim并且设置unstaked=false
        require(accountToStake[staker].unstakedTime > 86400 * 7, "it is unstaking");


        //也可以不做结算，做了可以加快结算
        _settleGlobalReward();
        _settleAccountReward(msg.sender);

        //unstake7天后解锁，claim时候进行处理
        //本金unstake
        IERC20(merlToken).transfer(staker, _amount);
        accountToStake[staker].unstaked = false;
        accountToStake[staker].unstakedTime = 0;

        //奖励unstake
        _withdrawReward(msg.sender);
    }

    //new
    function getStakeInfo(address _account) public view returns (uint256,uint256,uint256,uint256,uint256) {
        Stake storage stake = accountToStake[_account];
        uint256 lastUpdateTimestamp = globalReward.updateTimestamp;
        uint256 lastScaledTotalRewardPerMel = globalReward.scaledTotalRewardsPerMerl;
        uint256 scaledRangePerMerl = lastScaledTotalRewardPerMel - stake.reward.scaledSettledRewardPerMerl;
        uint256 rangeReward = _unscaleRangeReward(scaledRangePerMerl, stake.merl);
        uint256 settledReward = stake.rewards.settledRewardsEarned + rangeReward;
        return (stake.merl, settledReward, stake.rewards.rewardsClaimed, lastUpdateTimestamp, _unscale(lastScaledTotalRewardPerMel));
    }

    //new
    function getStakeInfoRealTime(address _account) external view returns (uint256,uint256,uint256,uint256,uint256) {
        Stake storage stake = accountToStake[_account];
        uint256 currentScaledTotalRewardPerMel = getCurrentScaledTotalRewardPerMerl();
        uint256 scaledRangePerMerl = currentScaledTotalRewardPerMel - stake.rewards.scaledSettledRewardPerMerl;
        uint256 rangeReward = _unscaleRangeReward(scaledRangePerMerl, stake.merl);
        uint256 settledReward = stake.rewards.settledRewardsEarned + rangeReward;
        return (stake.merl, settledReward, stake.rewards.rewardsClaimed, block.timestamp, _unscale(currentScaledTotalRewardPerMel));
    }

    //new
    function getAccountReward(address _account) external view returns (AccountReward memory) {
        Stake storage stake = accountToStake[_account];
        require(stake.account != address (0), "_account not exists");
        AccountReward memory accountReward = accountToStake[_account].rewards;
        accountReward.scaledSettledRewardPerMerl = _unscale(accountReward.scaledSettledRewardPerMerl);
        return accountReward;
    }

    //new
    function getTotalRewardInfo() public view returns(uint256,uint256,uint256,uint256,uint256) {
        uint256 lastTotalReward = globalReward.totalRewardsEarned;
        uint256 lastScaledTotalRewardPerMel = globalReward.scaledTotalRewardsPerMerl;
        uint256 lastTotalClaimedReward = globalReward.totalRewardsClaimed;
        uint256 lastUpdateTimestamp = globalReward.updateTimestamp;
        return (totalMerl, lastTotalReward, lastTotalClaimedReward, lastUpdateTimestamp, _unscale(lastScaledTotalRewardPerMel));
    }

    //new
    function getTotalRewardInfoRealTime() external view returns(uint256,uint256,uint256,uint256,uint256) {
        uint256 currentTotalReward = _getTotalReward();//new
        uint256 currentScaledTotalRewardPerMel = getCurrentScaledTotalRewardPerMerl();
        uint256 lastTotalClaimedReward = globalRewards.totalRewardsClaimed;
        return (totalMerl, currentTotalReward, lastTotalClaimedReward, block.timestamp, _unscale(currentScaledTotalRewardPerMel));
    }


    //new
    function _withdrawReward(address to) internal {
        Stake storage stake = accountToStake[to];
        AccountReward storage accountReward = stake.rewards;
        uint256 currentClaimReward = accountReward.settledRewardsEarned - accountReward.rewardsClaimed;

        accountReward.rewardsClaimed += currentClaimReward;
        globalReward.totalRewardsClaimed += currentClaimReward;

        require(currentClaimReward >0, "withdraw invalid amount");
        IERC20(merlToken).transfer(to, currentClaimReward);

        emit ClaimReward(
            to,
            merlToken,
            rewardToken,
            currentClaimReward,
            block.timestamp
        );
    }

    //new
    function _getRangeReward() internal returns(uint256){
        return 1;
    }

    //new
    function _settleGlobalReward() internal {
        uint256 rangeReward = _getRangeReward();
        if (rangeReward == 0) {
            globalReward.updateTimestamp = block.timestamp;
            return;
        }

        uint256 totalMerl = globalReward.totalRewardsEarned + rangeReward;
        uint256 scaledRangeRewardPerMerl = _scaledRangeRewardPerMerl(rangeReward, totalMerl);

        globalReward.scaledTotalRewardsPerMerl += scaledRangeRewardPerMerl;
        globalReward.totalRewardsEarned = totalReward;
        globalReward.updateTimestamp = block.timestamp;

        //新增奖励，判断rewardContract是不是有这么多才行？否则，提取奖励可能失败
//        if (rangeReward > 0) {
//            check IERC20(rewardContract).balance(merlToken) > totalReward - globalReward.totalRewardsClaimed;
//        }
    }

    //new
    function _settleAccountReward(address account) internal {
        Stake storage stake = accountToStake[account];
        if (stake.rewards.settledTimestamp == 0) {
            stake.rewards = AccountReward(
                0,
                0,
                block.timestamp,
                0
            );
        }

        AccountReward storage accountReward = stake.rewards;
        uint256 scaledRangeRewardPerMerl = globalReward.scaledTotalRewardsPerMerl - accountReward.scaledSettledRewardPerMerl;
        accountReward.settledRewardsEarned += _unscaleRangeReward(scaledRangeRewardPerMerl, stake.merl);
        accountReward.scaledSettledRewardPerMerl = globalReward.scaledTotalRewardsPerMerl;
        accountReward.settledTimestamp = block.timestamp;
    }

    function _unscaleRangeReward(uint256 _scaledTotalPerMer, uint256 _merl) internal pure returns(uint256) {
        return _unscale(_scaledTotalPerMer * _merl);
    }

    function _scaledRangeRewardPerMerl(uint256 _rangeReward, uint256 _totalMerl) internal pure returns(uint256) {
        return _scale(_rangeReward) / _totalMerl;
    }

    function _scale(uint256 _amount) internal pure returns(uint256) {
        return _amount * SCALE_FACTOR;
    }

    function _unscale(uint256 _amount) internal pure returns(uint256) {
        return _amount / SCALE_FACTOR;
    }

    //new
    function getCurrentScaledTotalRewardPerMerl() public view returns(uint256){
        uint256 totalReward = _getTotalReward(); //new
        uint256 scaledRangeRewardPerMerl = 0;
        if (totalMerl > 0) {
            scaledRangeRewardPerMerl = _scaledRangeRewardPerMerl(totalReward - globalReward.totalRewardsEarned, totalMerl);
        }
        return globalReward.scaledTotalRewardsPerMerl + scaledRangeRewardPerMerl;
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

