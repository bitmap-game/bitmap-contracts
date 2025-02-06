// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MerlSingleStake is OwnableUpgradeable {
    string public constant version = "1.0.0";
    uint256 public constant ONE_MERL = 1e18;
    uint256 public constant SCALE_FACTOR = 1e18;
    address public pauseAdmin;
    bool public paused;
    uint256 private _nonReentrantStatus;

    address public merlToken;
    address public rewardFromAddress;
    uint256 public totalMerl;

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

        AccountReward rewards;

        bool unstaking;
        uint256 unstakingMerl;
        uint256 unstakingReward;
        uint256 unstakingTime;

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
        rewardFromAddress = _rewardContract;

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

        Stake storage stake = accountToStake[msg.sender];
        if (stake.account == address(0)) {
            stake.account = staker;
            stake.updateTimestamp = block.timestamp;
        }
        _settleAccountReward(staker);
        stake.merl += _amount;
        stake.updateTimestamp = block.timestamp;

        emit StakeMerl(
            staker,
            _amount
        );
    }

    //new
    function unstakeMerl(uint256 _amount) external whenNotPaused nonReentrant {
        Stake storage stake = accountToStake[msg.sender];
        require(_amount > 0, "invalid _amount");
        require(stake.merl >= _amount, "Insufficient deposit");
        require(!stake.unstaking, "it is unstaking"); //必须是没有unstaked才能操作

        address staker = msg.sender;

        _settleGlobalReward();
        totalMerl -= _amount;

        _settleAccountReward(staker);
        stake.merl -= _amount;
        stake.unstaking = true;
        stake.unstakingMerl = _amount;
        stake.unstakingTime = time.Block;

        //calc newClaimReward
        AccountReward storage accountReward = stake.rewards;
        uint256 newClaimReward = accountReward.settledRewardsEarned - accountReward.rewardsClaimed;
        accountReward.rewardsClaimed += newClaimReward;
        globalReward.totalRewardsClaimed += newClaimReward;
        stake.unstakingReward = newClaimReward;
        stake.updateTimestamp = block.timestamp;

        emit UnstakeMerl(
            staker,
            stake.unstakingMerl,
            stake.unstakingReward
        );
    }

    //new
    function claimReward() external whenNotPaused nonReentrant {
        address staker = msg.sender;
        Stake storage stake = accountToStake[staker];
        require(stake.account != address (0), "invalid user");
        require(stake.unstaking, "it is not unstaking"); //必须是unstaked才能操作
        require(stake.unstakingTime > 86400 * 7, "it is unstaking in 7 days"); //unstake7天后解锁,并且设置unstaked=false

        IERC20(merlToken).transfer(staker, stake.unstakingMerl); //unstakingMerl
        stake.unstaking = false;
        stake.unstakingTime = 0;

        require(stake.unstakingReward > 0, "claim invalid amount");
        IERC20(merlToken).transferFrom(rewardFromAddress, to, stake.unstakingReward); //unstakingReward
        stake.updateTimestamp = block.timestamp;

        emit ClaimReward(
            staker,
            rewardFromAddress,
            to,
            stake.unstakingMerl,
            stake.unstakingReward,
            block.timestamp
        );
    }

    //new
    function getStakeInfo(address _account) public view returns (Stake memory) {
        Stake memory stakeMem = accountToStake[_account];
        //stakeMem.rewards.scaledSettledRewardPerMerl = currentScaledTotalRewardPerMel;
        stakeMem.rewards.scaledSettledRewardPerMerl = _unscale(stakeMem.rewards.scaledSettledRewardPerMerl);
        return (stakeMem);
    }

    //new
    function getStakeInfoRealTime(address _account) external view returns (Stake memory) {
        Stake memory stakeMem = accountToStake[_account];
        uint256 currentScaledTotalRewardPerMel = getCurrentScaledTotalRewardPerMerl();
        uint256 scaledRangePerMerl = currentScaledTotalRewardPerMel - stakeMem.rewards.scaledSettledRewardPerMerl;
        uint256 rangeReward = _unscaleRangeReward(scaledRangePerMerl, stakeMem.merl);
        uint256 settledReward = stakeMem.rewards.settledRewardsEarned + rangeReward;

        stakeMem.rewards.settledRewardsEarned = settledReward;
        //stakeMem.rewards.scaledSettledRewardPerMerl = currentScaledTotalRewardPerMel;
        stakeMem.rewards.scaledSettledRewardPerMerl = _unscale(currentScaledTotalRewardPerMel);
        stakeMem.rewards.settledTimestamp = block.timestamp;

        return (stakeMem);
    }

    //new
    function getTotalRewardInfo() public view returns(uint256,GlobalReward memory) {
        GlobalReward memory globalRewardMem = globalReward;
        globalRewardMem.scaledTotalRewardsPerMerl = _unscale(globalRewardMem.scaledTotalRewardsPerMerl);
        return (totalMerl, globalRewardMem);
    }

    //new
    function getTotalRewardInfoRealTime() external view returns(uint256,GlobalReward memory) {
        GlobalReward memory globalRewardMem = globalReward;
        globalRewardMem.totalRewardsEarned = _getTotalReward();//new
        globalRewardMem.scaledTotalRewardsPerMerl = _unscale(globalRewardMem.scaledTotalRewardsPerMerl);
        globalRewardMem.updateTimestamp = block.timestamp;
        return (totalMerl, globalRewardMem);
    }

    //new
    function _getRangeReward() internal returns(uint256){
        return totalMerl * apy / 365 / 86400;
    }

    //new
    function _settleGlobalReward() internal {
        uint256 rangeReward = _getRangeReward();
        if (rangeReward == 0) {
            globalReward.updateTimestamp = block.timestamp;
            return;
        }
        uint256 scaledRangeRewardPerMerl = _scaledRangeRewardPerMerl(rangeReward, totalMerl);

        globalReward.scaledTotalRewardsPerMerl += scaledRangeRewardPerMerl;
        globalReward.totalRewardsEarned = totalReward;
        globalReward.updateTimestamp = block.timestamp;

        //todo 新增奖励，判断rewardContract是不是有这么多才行？否则，提取奖励可能失败
        //if (rangeReward > 0) {
        //    check IERC20(rewardContract).balance(merlToken) > totalReward - globalReward.totalRewardsClaimed;
        //}
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

