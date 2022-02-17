// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract LPFarmStorage {
    // Info of each user.
    struct UserInfo {
        uint amount;     // How many LP tokens the user has provided.
        uint rewardDebt; // Reward debt. See explanation below.
    }
    // Info of each pool.
    struct PoolInfo {
        address lpToken;           // Address of LP token contract.
        uint allocPoint;       // How many allocation points assigned to this pool.
        uint lastRewardTime;  // Last block number that rewards distribution occurs.
        uint accRewardsPerShare; // Accumulated rewards per share, times 1e12. See below.
    }
    address public rewardToken;
    // reward tokens created per second.
    uint public rewardsPerSecond;
    // Bonus muliplier for early reward makers.
    uint public bounsMultiplier;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint public totalAllocPoint;
    // The block number when reward mining starts.
    uint public startTime;
    uint public endTime;
    mapping (address => bool) tokenAddedList;
    mapping (address => uint) public lpTokenTotal;
    mapping (address => uint) public rewardBalances;
}

contract LPFarm is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, LPFarmStorage{
    using SafeERC20 for IERC20;

    uint public constant PRECISION = 1e12;
    event Deposit(address indexed payer, address indexed user, uint indexed pid, uint amount);
    event Withdraw(address indexed user, uint indexed pid, uint amount);
    event ClaimRewards(address indexed user,uint256 indexed pid,uint256 rewardAmount);
    event NewRewardsPerSecond(uint newrewardsPerSecond, uint oldrewardsPerSecond);
    function initialize(
        address _rewardToken,
        uint _rewardsPerSecond,
        uint _startTime,
        uint _endTime
    ) public initializer {
        rewardToken = _rewardToken;
        rewardsPerSecond = _rewardsPerSecond;
        startTime = _startTime;
        endTime = _endTime;
        totalAllocPoint = 0;
        bounsMultiplier = 1;
        __Ownable_init();
        __ReentrancyGuard_init();
    }
    function updateMultiplier(uint multiplierNumber) public onlyOwner {
        _updateAllPools();
        bounsMultiplier = multiplierNumber;
    }
    function add(uint _allocPoint, address _lpToken, bool _withUpdate) public onlyOwner {
        require(!tokenAddedList[_lpToken], "token exists");
        if (_withUpdate) {
            _updateAllPools();
        }
        uint lastRewardTime = getBlockTimestamp() > startTime ? getBlockTimestamp() : startTime;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardTime: lastRewardTime,
            accRewardsPerShare: 0
        }));
        tokenAddedList[_lpToken] = true;
        updateStakingPool();
    }
    function set(uint _pid, uint _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            _updateAllPools();
        }
        uint prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            updateStakingPool();
        }
    }
    function updateStakingPool() internal {
        uint length = poolInfo.length;
        uint points = 0;
        for (uint pid = 0; pid < length; ++pid) {
            points = points + poolInfo[pid].allocPoint;
        }
        totalAllocPoint = points;
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
    function pendingRewards(uint _pid, address _user) external view returns (uint) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint accRewardsPerShare = pool.accRewardsPerShare;
        uint lpSupply = lpTokenTotal[pool.lpToken];
        if (getBlockTimestamp() > pool.lastRewardTime && lpSupply != 0) {
            uint multiplier = getMultiplier(pool.lastRewardTime, getBlockTimestamp());
            uint rewardsReward = multiplier * rewardsPerSecond * pool.allocPoint / totalAllocPoint;
            accRewardsPerShare = accRewardsPerShare + rewardsReward * PRECISION / lpSupply;
        }
        return user.amount * accRewardsPerShare / PRECISION - user.rewardDebt;
    }
    function updateAllPools() external {
        _updateAllPools();
    }
    function _updateAllPools() internal {
        uint length = poolInfo.length;
        for (uint pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }
    function updatePool(uint _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        if (getBlockTimestamp() <= pool.lastRewardTime) {
            return;
        }
        uint lpSupply = lpTokenTotal[pool.lpToken];
        if (lpSupply == 0) {
            pool.lastRewardTime = getBlockTimestamp();
            return;
        }
        uint multiplier = getMultiplier(pool.lastRewardTime, getBlockTimestamp());
        uint rewardAmount = multiplier * rewardsPerSecond * pool.allocPoint / totalAllocPoint;
        pool.accRewardsPerShare = pool.accRewardsPerShare + rewardAmount * PRECISION / lpSupply;
        pool.lastRewardTime = getBlockTimestamp();
    }
    function deposit(uint _pid, uint _amount) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint pending = user.amount * pool.accRewardsPerShare / PRECISION - user.rewardDebt;
            if(pending > 0) {
                safeRewardsTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            IERC20(pool.lpToken).safeTransferFrom(msg.sender, address(this), _amount);
            user.amount += _amount;
        }
        user.rewardDebt = user.amount * pool.accRewardsPerShare / PRECISION;
        lpTokenTotal[pool.lpToken] += _amount;
        emit Deposit(msg.sender, msg.sender, _pid, _amount);
    }
    function claimRewards(address _account) external nonReentrant {
        uint pending;
        for(uint256 i = 0; i < poolInfo.length; i++){ 
            PoolInfo storage pool = poolInfo[i];
            UserInfo storage user = userInfo[i][_account];
            updatePool(i);
            if (user.amount > 0) {
                uint256 reward = user.amount * pool.accRewardsPerShare / PRECISION - user.rewardDebt;
                pending += reward;
                emit ClaimRewards(_account, i, reward);
            }
            user.rewardDebt = user.amount * pool.accRewardsPerShare / PRECISION;
        }
        uint256 balance = IERC20(rewardToken).balanceOf(address(this));
        if(pending > 0 && pending <= balance) {
            safeRewardsTransfer(_account, pending);
        }
    }
    function depositBehalf(address _account, uint _pid, uint _amount) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_account];
        updatePool(_pid);
        if (user.amount > 0) {
            uint pending = user.amount * pool.accRewardsPerShare / PRECISION - user.rewardDebt;
            if(pending > 0) {
                safeRewardsTransfer(_account, pending);
            }
        }
        if (_amount > 0) {
            IERC20(pool.lpToken).safeTransferFrom(msg.sender, address(this), _amount);
            user.amount += _amount;
        }
        user.rewardDebt = user.amount * pool.accRewardsPerShare / PRECISION;
        lpTokenTotal[pool.lpToken] += _amount;
        emit Deposit(msg.sender, _account, _pid, _amount);
    }
    function withdraw(uint _pid, uint _amount) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "lpToken insufficient");
        updatePool(_pid);
        uint pending = user.amount * pool.accRewardsPerShare / PRECISION - user.rewardDebt;
        if(_amount > 0) {
            user.amount -= _amount;
            lpTokenTotal[pool.lpToken] -= _amount;
            IERC20(pool.lpToken).safeTransfer(msg.sender, _amount);
        }
        user.rewardDebt = user.amount * pool.accRewardsPerShare / PRECISION;
        if(pending > 0) {
            safeRewardsTransfer(msg.sender, pending);
        }
        emit Withdraw(msg.sender, _pid, _amount);
    }
    function safeRewardsTransfer(address to, uint amount) internal {
        uint rewardTokenBalance = IERC20(rewardToken).balanceOf(address(this));
        if(amount > rewardTokenBalance) {
            IERC20(rewardToken).safeTransfer(to, rewardTokenBalance);
        } else {
            IERC20(rewardToken).safeTransfer(to, amount);
        }
    }
    function getPoolSize() external view returns(uint) {
        return poolInfo.length;
    }
    function setRewardsPerSecond(uint _rewardsPerSecond) external onlyOwner {
        _updateAllPools();
        uint oldrewardsPerSecond = rewardsPerSecond;
        rewardsPerSecond = _rewardsPerSecond;
        emit NewRewardsPerSecond(rewardsPerSecond, oldrewardsPerSecond);
    }
    function getBlockTimestamp() internal view returns (uint) {
        //solium-disable-next-line
        return block.timestamp;
    }
}