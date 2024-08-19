// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IRewardContract.sol";

contract MerlStake is OwnableUpgradeable {
    string public constant version = "1.0.0";
    uint256 public constant ONE_MERL = 1e18;
    uint256 public constant SCALE_FACTOR = 1e18;
    address public pauseAdmin;
    bool public paused;
    uint256 private _nonReentrantStatus;

    address public merlContract;
    uint256 public totalMerl;

    struct GlobalReward {
        address rewardContract;
        address rewardToken;
        uint256 totalRewardsEarned;
        uint256 scaledTotalRewardsPerMerl;
        uint256 totalRewardsClaimed;
        uint256 updateTimestamp;
        bool enabled; //if false, can not settle and withdraw.
    }

    mapping(address => GlobalReward) public globalRewards;

    address[] public globalRewardContracts;

    struct AccountReward {
        uint256 scaledSettledRewardPerMerl;
        uint256 settledRewardsEarned;
        uint256 settledTimestamp;
        uint256 rewardsClaimed;
    }

    struct Stake {
        address account;
        uint256 merl;
        mapping(address => AccountReward) rewards;
        uint256 stakeTimestamp;
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

    event AddRewardContract(
        address adminSetter,
        address rewardContract
    );

    event DisableRewardContract(
        address adminSetter,
        address rewardContract
    );

    event EnableRewardContract(
        address adminSetter,
        address rewardContract
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
    * - `_merlContract`: stake merl to get rewards.
    */
    function initialize(
        address _initialOwner,
        address _merlContract
    ) external
    onlyValidAddress(_initialOwner)
    onlyValidAddress(_merlContract) initializer {
        merlContract = _merlContract;

        // Initialize OZ contracts
        __Ownable_init_unchained(_initialOwner);
    }

    /**
    * @dev Stake merl: stake merl in contract, we will get rewards. we can continuously stake and unstake the merl.
    *
    * - `_amount`: stake the merl amount, at least 1 merl.
    *
    * Firstly, we transfer the specified amount of merl from sender to this contract.
    * and then, we update the global all rewards, and the range reward from reward contract to this contract.
    * and then, we settle this account all rewards.
    * finally, we update account's merl and global total merl.
    */
    function stakeMerl(uint256 _amount) external whenNotPaused nonReentrant {
        require(_amount >= ONE_MERL, "at least 1 MERL");

        address staker = msg.sender;
        IERC20(merlContract).transferFrom(staker, address(this), _amount);

        _settleGlobalAllRewards();

        if (accountToStake[staker].account == address(0)) {
            accountToStake[staker].account = staker;
            accountToStake[staker].stakeTimestamp = block.timestamp;
        }

        _settleAccountAllRewards(staker);

        accountToStake[staker].merl += _amount;

        totalMerl += _amount;

        emit StakeMerl(
            staker,
            _amount
        );
    }

    /**
    * @dev Unstake merl: unstake merl from contract, in the meantime, we claim all rewards.
    *
    * - `_amount`: unstake the merl amount.
    * - `_isClaim`: when we unsatke the merl, whether we claim rewards or not.
    *
    * Firstly, we settle the global all rewards, and transfer the range reward from reward contract to this contract.
    * and then, we settle this account all rewards.
    * and then, we update account's merl and global total merl.
    * finally, we transfer the specified amount of merl to this account. if _isClaim is true, we also claim all rewards.
    */
    function unstakeMerl(uint256 _amount, bool _isClaim) external whenNotPaused nonReentrant {
        require(_amount > 0, "invalid _amount");
        require(accountToStake[msg.sender].merl >= _amount, "Insufficient deposit");

        address staker = msg.sender;

        _settleGlobalAllRewards();

        _settleAccountAllRewards(staker);

        accountToStake[staker].merl -= _amount;

        totalMerl -= _amount;

        IERC20(merlContract).transfer(staker, _amount);

        if (_isClaim) {
            _withdrawAllReward(msg.sender);
        }

        emit UnstakeMerl(
            staker,
            _amount
        );
    }

    /**
    * @dev Claim reward: we claim the specified contract reward.
    *
    * - `_rewardContract`: the specified reward contract.
    *
    * Firstly, we settle the global reward for the specified contract, and transfer the range reward from
    *   reward contract to this contract.
    * and then, we settle this account the specified contract rewards.
    * finally, we claim the specified reward to this account.
    */
    function claimReward(address _rewardContract) external whenNotPaused nonReentrant {
        require(accountToStake[msg.sender].account != address (0), "invalid user");
        require(globalRewards[_rewardContract].enabled, "reward disabled");

        _settleGlobalReward(_rewardContract);

        _settleAccountReward(msg.sender, _rewardContract);

        _withdrawReward(msg.sender, _rewardContract);
    }

    /**
    * @dev Claim all reward: we claim all reward from this contract.
    *
    * Firstly, we settle the global all rewards, and transfer the range reward from reward contract to this contract.
    * and then, we settle this account all rewards.
    * and then, we update account's merl and global total merl.
    * finally, we transfer all reward to this account.
    */
    function claimAllReward() external whenNotPaused nonReentrant {
        require(accountToStake[msg.sender].account != address (0), "invalid user");

        _settleGlobalAllRewards();

        _settleAccountAllRewards(msg.sender);

        _withdrawAllReward(msg.sender);
    }

    /**
    * @dev Get account stake info.
    *
    * - `_account`: the account address that we are looking for.
    * - `_rewardContract`: the specified reward contract.
    *
    * return this account stake info with (merl, settledReward, rewardsClaimed, blockTime, perMerl).
    */
    function getStakeInfo(address _account, address _rewardContract) external view returns (uint256,uint256,uint256,uint256,uint256) {
        Stake storage stake = accountToStake[_account];
        uint256 lastUpdateTimestamp = globalRewards[_rewardContract].updateTimestamp;
        uint256 lastScaledTotalRewardPerMel = globalRewards[_rewardContract].scaledTotalRewardsPerMerl;
        uint256 scaledRangePerMerl = lastScaledTotalRewardPerMel - stake.rewards[_rewardContract].scaledSettledRewardPerMerl;
        uint256 rangeReward = _unscaleRangeReward(scaledRangePerMerl, stake.merl);
        uint256 settledReward = stake.rewards[_rewardContract].settledRewardsEarned + rangeReward;
        return (stake.merl, settledReward, stake.rewards[_rewardContract].rewardsClaimed, lastUpdateTimestamp, _unscale(lastScaledTotalRewardPerMel));
    }

    /**
    * @dev Get real time account stake info.
    *
    * - `_account`: the account address that we are looking for.
    * - `_rewardContract`: the specified reward contract.
    *
    * Firstly, we calculate the current scaled range reward per merl, then get rangeReward.
    * And then, we calculate real time settledReward with the current scaled range reward per merl.
    * finally, return this account real time stake info with (merl, settledReward, rewardsClaimed, blockTime, perMerl)
    */
    function getStakeInfoRealTime(address _account, address _rewardContract) external view returns (uint256,uint256,uint256,uint256,uint256) {
        Stake storage stake = accountToStake[_account];
        uint256 currentScaledTotalRewardPerMel = getCurrentScaledTotalRewardPerMerl(_rewardContract);
        uint256 scaledRangePerMerl = currentScaledTotalRewardPerMel - stake.rewards[_rewardContract].scaledSettledRewardPerMerl;
        uint256 rangeReward = _unscaleRangeReward(scaledRangePerMerl, stake.merl);
        uint256 settledReward = stake.rewards[_rewardContract].settledRewardsEarned + rangeReward;
        return (stake.merl, settledReward, stake.rewards[_rewardContract].rewardsClaimed, block.timestamp, _unscale(currentScaledTotalRewardPerMel));
    }

    /**
    * @dev Get account reward info.
    *
    * - `_account`: the account address that we are looking for.
    * - `_rewardContract`: the specified reward contract.
    */
    function getAccountReward(address _account, address _rewardContract) external view returns (AccountReward memory) {
        Stake storage stake = accountToStake[_account];
        require(stake.account != address (0), "_account not exists");
        AccountReward memory accountReward = accountToStake[_account].rewards[_rewardContract];
        accountReward.scaledSettledRewardPerMerl = _unscale(accountReward.scaledSettledRewardPerMerl);
        return accountReward;
    }

    /**
    * @dev Get the last total reward info.
    *
    * - `_rewardContract`: the specified reward contract.
    */
    function getTotalRewardInfo(address _rewardContract) external view returns(uint256,uint256,uint256,uint256,uint256) {
        uint256 lastTotalReward = globalRewards[_rewardContract].totalRewardsEarned;
        uint256 lastScaledTotalRewardPerMel = globalRewards[_rewardContract].scaledTotalRewardsPerMerl;
        uint256 lastTotalClaimedReward = globalRewards[_rewardContract].totalRewardsClaimed;
        uint256 lastUpdateTimestamp = globalRewards[_rewardContract].updateTimestamp;
        return (totalMerl, lastTotalReward, lastTotalClaimedReward, lastUpdateTimestamp, _unscale(lastScaledTotalRewardPerMel));
    }

    /**
    * @dev Get real time total reward.
    *
    * - `_rewardContract`: the specified reward contract.
    *
    * Firstly, we get current total reward from the specified reward contract.
    * And then, we calculate the current scaled range reward per merl.
    * finally, we return the global real time reward info.
    */
    function getTotalRewardInfoRealTime(address _rewardContract) external view returns(uint256,uint256,uint256,uint256,uint256) {
        uint256 currentTotalReward = IRewardContract(_rewardContract).getTotalReward();
        uint256 currentScaledTotalRewardPerMel = getCurrentScaledTotalRewardPerMerl(_rewardContract);
        uint256 lastTotalClaimedReward = globalRewards[_rewardContract].totalRewardsClaimed;
        return (totalMerl, currentTotalReward, lastTotalClaimedReward, block.timestamp, _unscale(currentScaledTotalRewardPerMel));
    }

    /**
    * @dev Add a new reward contract, then all users that stake merl will get reward from it. Please double-check
    *   whether the reward contract address is correct when adding.
    * (only by owner)
    */
    function addRewardContract(address _rewardContract) external onlyOwner {
        require(_rewardContract != address(0), "invalid _rewardContract");
        require(globalRewards[_rewardContract].updateTimestamp == 0, "_rewardContract is already exist");

        address rewardToken = IRewardContract(_rewardContract).getRewardToken();
        GlobalReward memory reward = GlobalReward(
            _rewardContract,
            rewardToken,
            0,
            0,
            0,
            block.timestamp,
            true
        );
        globalRewards[_rewardContract] = reward;

        globalRewardContracts.push(_rewardContract);

        emit AddRewardContract(msg.sender, _rewardContract);
    }

    /**
    * @dev Disable the specified reward contract, then we can't settle this contract reward, and can't get reward.
    * (only by owner)
    */
    function disableRewardContract(address _rewardContract) external onlyOwner {
        require(_rewardContract != address(0), "invalid _rewardContract");
        require(globalRewards[_rewardContract].enabled == true, "_rewardContract is disable");

        globalRewards[_rewardContract].enabled = false;

        emit DisableRewardContract(msg.sender, _rewardContract);
    }

    /**
    * @dev Enable the specified reward contract, then we can settle this contract reward, and get reward.
    * (only by owner)
    */
    function enableRewardContract(address _rewardContract) external onlyOwner {
        require(_rewardContract != address(0), "invalid _rewardContract");
        require(globalRewards[_rewardContract].enabled == false, "_rewardContract is enable");

        globalRewards[_rewardContract].enabled = true;

        emit EnableRewardContract(msg.sender, _rewardContract);
    }

    /**
    * @dev List all reward contracts.
    *
    * - `_all`: if true, list all reward contracts; if false, list valid reward contracts.
    */
    function listRewardContract(bool all) external view returns (address[] memory) {
        if (all) {
            return _getRewardContract();
        }

        return _getValidRewardContract();
    }

    function _getRewardContract() internal view returns(address[] memory) {
        return globalRewardContracts;
    }

    function _getValidRewardContract() internal view returns (address[] memory) {
        uint16 count = 0;
        for (uint16 i=0; i<globalRewardContracts.length; i++) {
            if (globalRewards[globalRewardContracts[i]].enabled) {
                count += 1;
            }
        }

        address[] memory contracts = new address[](count);
        uint16 j = 0;
        for (uint16 i=0; i<globalRewardContracts.length; i++) {
            if (globalRewards[globalRewardContracts[i]].enabled) {
                contracts[j] = globalRewardContracts[i];
                j += 1;
            }
        }

        return contracts;
    }

    function _withdrawAllReward(address to) internal {
        for (uint16 i=0; i< globalRewardContracts.length; i++) {
            address rewardContract = globalRewardContracts[i];
            if (globalRewards[rewardContract].enabled) {
                _withdrawReward(to, rewardContract);
            }
        }
    }
    function _withdrawReward(address to, address rewardContract) internal {
        Stake storage stake = accountToStake[to];
        AccountReward storage accountReward = stake.rewards[rewardContract];
        uint256 currentClaimReward = accountReward.settledRewardsEarned - accountReward.rewardsClaimed;

        accountReward.rewardsClaimed += currentClaimReward;
        globalRewards[rewardContract].totalRewardsClaimed += currentClaimReward;

        address rewardToken = globalRewards[rewardContract].rewardToken;

        require(currentClaimReward >0, "withdraw invalid amount");
        IERC20(rewardToken).transfer(to, currentClaimReward);

        emit ClaimReward(
            to,
            rewardContract,
            rewardToken,
            currentClaimReward,
            block.timestamp
        );
    }

    function _settleGlobalAllRewards() internal {
        for (uint16 i=0; i< globalRewardContracts.length; i++) {
            address rewardContract = globalRewardContracts[i];
            if (globalRewards[rewardContract].enabled) {
                _settleGlobalReward(rewardContract);
            }
        }
    }

    function _settleGlobalReward(address rewardContract) internal {
        GlobalReward storage globalReward = globalRewards[rewardContract];
        uint256 totalReward = IRewardContract(rewardContract).getTotalReward();
        require(totalReward >= globalReward.totalRewardsEarned, "invalid totalReward");

        uint256 rangeReward = totalReward - globalReward.totalRewardsEarned;
        if (rangeReward == 0) {
            globalReward.updateTimestamp = block.timestamp;
            return;
        }

        uint256 scaledRangeRewardPerMerl = 0;
        if (totalMerl > 0) {
            scaledRangeRewardPerMerl = _scaledRangeRewardPerMerl(rangeReward, totalMerl);
        }
        globalReward.scaledTotalRewardsPerMerl += scaledRangeRewardPerMerl;
        globalReward.totalRewardsEarned = totalReward;
        globalReward.updateTimestamp = block.timestamp;

        //withdraw reward from rewardContract.
        if (rangeReward > 0) {
            IRewardContract(rewardContract).withdrawReward(rangeReward);
        }
    }

    function _settleAccountAllRewards(address account) internal {
        for (uint16 i=0; i< globalRewardContracts.length; i++) {
            address rewardContract = globalRewardContracts[i];
            if (globalRewards[rewardContract].enabled) {
                _settleAccountReward(account, rewardContract);
            }
        }
    }

    function _settleAccountReward(address account, address rewardContract) internal {
        Stake storage stake = accountToStake[account];
        GlobalReward storage globalReward = globalRewards[rewardContract];
        if (stake.rewards[rewardContract].settledTimestamp == 0) {
            stake.rewards[rewardContract] = AccountReward(
                0,
                0,
                block.timestamp,
                0
            );
        }

        AccountReward storage accountReward = stake.rewards[rewardContract];
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

    /**
    * @dev Get current scaled total reward per merl.
    */
    function getCurrentScaledTotalRewardPerMerl(address rewardContract) public view returns(uint256){
        GlobalReward memory globalReward = globalRewards[rewardContract];
        uint256 totalReward = IRewardContract(rewardContract).getTotalReward();
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

