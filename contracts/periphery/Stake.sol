// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./library/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// storge contract
contract StakeStorage {
    address public stakeToken;
    address public rewardsToken;
    uint public rewardsPerSecond;
    uint public bounsMultiplier;
    uint public startTime;
    uint public endTime;
    uint public stakeTokenTotal;
    uint public accRewardsPerShare;
    uint public lastRewardBlockTimestamp;
    mapping(address => uint) public userStakeTime;
    mapping(address => uint) public stakeBalance;
    mapping(address => uint) public rewardDebt;
}

contract Stake is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, StakeStorage{
    uint public constant PRECISION = 1e12;
    uint public constant BONUS_MULTIPLIER_MAX = 100;
    uint public constant REWARDS_PER_MAX = 100e18;
    event Stake(address staker, uint256 amount);
    event Withdraw(address staker, uint256 amount, uint256 remainingAmount);
    event ClaimReward(address indexed user, uint256 tokenReward);
    event NewVoteToken(address newVoteToken, address oldVoteToken);
    event NewRewardsPerSecond(uint newRewardsPerSecond, uint oldRewardsPerSecond);
    event NewMultiplier(uint newMultiplier, uint oldMultiplier);
    function initialize(address _stakeToken, address _rewardsToken, uint _startTime, uint _endTime) public initializer{
        require(_stakeToken != address(0), "invalid address");
        require(_rewardsToken != address(0), "invalid address");
        __Ownable_init();
        __ReentrancyGuard_init();
        stakeToken = _stakeToken;
        rewardsToken = _rewardsToken;
        startTime = _startTime;
        endTime = _endTime;
        bounsMultiplier = 1;
    }
    function updateMultiplier(uint multiplierNumber) public onlyOwner {
        require(multiplierNumber <= BONUS_MULTIPLIER_MAX, "too large");
        updatePool();
        emit NewMultiplier(multiplierNumber, bounsMultiplier);
        bounsMultiplier = multiplierNumber;
    }
    function setRewardsPerSecond(uint _rewardsPerSecond) external onlyOwner {
        require(_rewardsPerSecond <= REWARDS_PER_MAX, "too large");
        updatePool();
        emit NewRewardsPerSecond(_rewardsPerSecond, rewardsPerSecond);
        rewardsPerSecond = _rewardsPerSecond;
        
    }
    function getMultiplier(uint _from, uint _to) internal view returns (uint) {
        if (_to <= endTime) {
            return (_to - _from) * bounsMultiplier;
        } else if (_from >= endTime) {
            return 0;
        } else {
            return (endTime - _from) * bounsMultiplier;
        }
    }
    function updatePool() internal {
        if (getBlockTimestamp() <= lastRewardBlockTimestamp) {
            return;
        }
        if (stakeTokenTotal == 0) {
            lastRewardBlockTimestamp = getBlockTimestamp();
            return;
        } 
        uint multiplier = getMultiplier(lastRewardBlockTimestamp, getBlockTimestamp());
        uint tokenReward = multiplier * rewardsPerSecond;
        accRewardsPerShare = accRewardsPerShare + tokenReward * PRECISION / stakeTokenTotal;
        lastRewardBlockTimestamp = getBlockTimestamp();
    }
    function stake(uint amount) external {
        require(amount > 0, "amount error");
        updatePool();
        TransferHelper.safeTransferFrom(stakeToken, msg.sender, address(this), amount);
        if (stakeBalance[msg.sender] > 0) {
            uint256 reward = _estimateRewards(msg.sender);
            safeRewardsTransfer(msg.sender, reward);
            emit ClaimReward(msg.sender, reward);
        }
        userStakeTime[msg.sender] = getBlockTimestamp();
        stakeBalance[msg.sender] += amount;
        stakeTokenTotal += amount;
        rewardDebt[msg.sender] = stakeBalance[msg.sender] * accRewardsPerShare / PRECISION;
        emit Stake(msg.sender, amount);
    }
    function withdraw(uint amount) external {
        require(stakeBalance[msg.sender] >= amount, "insufficient balance");
        updatePool();
        if (stakeBalance[msg.sender] > 0) {
            uint256 reward = _estimateRewards(msg.sender);
            safeRewardsTransfer(msg.sender, reward);
            emit ClaimReward(msg.sender, reward);
        }
        stakeBalance[msg.sender] -= amount;
        stakeTokenTotal -=amount;
        rewardDebt[msg.sender] = stakeBalance[msg.sender] * accRewardsPerShare / PRECISION;
        TransferHelper.safeTransfer(stakeToken, msg.sender, amount);
        emit Withdraw(msg.sender, amount, stakeBalance[msg.sender]);
    }
    function estimateRewards(address account) external view returns (uint) {
        if (getBlockTimestamp() <= lastRewardBlockTimestamp) {
            return 0;
        }
        if (stakeTokenTotal == 0) {
            return 0;
        } 
        uint multiplier = getMultiplier(lastRewardBlockTimestamp, getBlockTimestamp());
        uint tokenReward = multiplier * rewardsPerSecond;
        uint tempAccRewardsPerShare = accRewardsPerShare + tokenReward * PRECISION / stakeTokenTotal;
        return stakeBalance[account] * tempAccRewardsPerShare / PRECISION - rewardDebt[account];
        // return _estimateRewards(account);
    }
    function _estimateRewards(address account) internal view returns (uint) {
        if(stakeBalance[account] == 0){
            return 0;
        }
        return stakeBalance[account] * accRewardsPerShare / PRECISION - rewardDebt[account];
    }
    function claimReward(address _account) external nonReentrant {
        updatePool();
        if (stakeBalance[_account] > 0) {
            uint256 reward = _estimateRewards(_account);
            rewardDebt[_account] = stakeBalance[_account] * accRewardsPerShare / PRECISION;
            safeRewardsTransfer(_account, reward);
            emit ClaimReward(_account, reward);
        }
    }
    function getBlockTimestamp() internal view returns (uint) {
        // solhint-disable-next-line not-rely-on-time
        return block.timestamp;
    }
    function safeRewardsTransfer(address to, uint amount) internal {
        // TransferHelper.safeTransfer(rewardsToken, to, amount);
        uint rewardTokenBalance = IERC20(rewardsToken).balanceOf(address(this));
        if(amount > rewardTokenBalance) {
            TransferHelper.safeTransfer(rewardsToken, to, rewardTokenBalance);
        } else {
            TransferHelper.safeTransfer(rewardsToken, to, amount);
        }
    }
}