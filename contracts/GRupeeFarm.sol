// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
/*
 _    _ __     __ _____   _    _  _       ______   _____ __          __       _____
| |  | |\ \   / /|  __ \ | |  | || |     |  ____| / ____|\ \        / //\    |  __ \
| |__| | \ \_/ / | |__) || |  | || |     | |__   | (___   \ \  /\  / //  \   | |__) |
|  __  |  \   /  |  _  / | |  | || |     |  __|   \___ \   \ \/  \/ // /\ \  |  ___/
| |  | |   | |   | | \ \ | |__| || |____ | |____  ____) |   \  /\  // ____ \ | |
|_|  |_|   |_|   |_|  \_\ \____/ |______||______||_____/     \/  \//_/    \_\|_|

*/

// Libraries
import "../libraries/GoldenRupee.sol";

// Interfaces
import "../interfaces/IBEP20.sol";
import "../interfaces/SafeBEP20.sol";
import "../interfaces/IStrategy.sol";

//Openzeppelin
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract GRupeeFarm is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    //-------------------------------------------------------------------------
    // STRUCTS
    //-------------------------------------------------------------------------

    struct UserInfo {
        uint256 shares;
        uint256 rewardDebt;
    }

    struct PoolInfo {
        IBEP20 want;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accGRupeePerShare;
        address strategy;
    }

    //-------------------------------------------------------------------------
    // ADDRESSES
    //-------------------------------------------------------------------------

    address public GRUPEE;
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;

    //-------------------------------------------------------------------------
    // ATTRIBUTES
    //-------------------------------------------------------------------------

    uint256 public teamAllocated = 120; // 12%

    uint256 public GRUPEEMaxSupply = 200000e18; // 200k
    uint256 public GRUPEEPerBlock = 10000000000000000; // 0.01 per block
    uint256 public startBlock = 6451189; // Sat Apr 10 2021 21:00:02 GMT+0200

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    uint256 public totalAllocPoint = 0;

    //-------------------------------------------------------------------------
    // EVENTS
    //-------------------------------------------------------------------------

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(address _grupee) public {
        GRUPEE = _grupee;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function add(
        uint256 _allocPoint,
        IBEP20 _want,
        bool _withUpdate,
        address _strategy
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 _lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({want: _want, allocPoint: _allocPoint, lastRewardBlock: _lastRewardBlock, accGRupeePerShare: 0, strategy: _strategy})
        );
    }

    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (IBEP20(GRUPEE).totalSupply() >= GRUPEEMaxSupply) {
            return 0;
        }
        return _to.sub(_from);
    }

    function pendingGRUPEE(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accGRupeePerShare = pool.accGRupeePerShare;
        uint256 sharesTotal = IStrategy(pool.strategy).sharesTotal();

        if (block.number > pool.lastRewardBlock && sharesTotal != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 GRupeeReward = multiplier.mul(GRUPEEPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accGRupeePerShare = accGRupeePerShare.add(GRupeeReward.mul(1e12).div(sharesTotal));
        }
        return user.shares.mul(accGRupeePerShare).div(1e12).sub(user.rewardDebt);
    }

    function stakedWantTokens(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 sharesTotal = IStrategy(pool.strategy).sharesTotal();
        uint256 wantLockedTotal = IStrategy(poolInfo[_pid].strategy).wantLockedTotal();

        if (sharesTotal == 0) {
            return 0;
        }

        return user.shares.mul(wantLockedTotal).div(sharesTotal);
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];

        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        uint256 sharesTotal = IStrategy(pool.strategy).sharesTotal();
        if (sharesTotal == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        if (multiplier <= 0) {
            return;
        }

        uint256 GRUPEEReward = multiplier.mul(GRUPEEPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        GoldenRupee(GRUPEE).mint(owner(), GRUPEEReward.mul(teamAllocated).div(1000));
        GoldenRupee(GRUPEE).mint(address(this), GRUPEEReward);

        pool.accGRupeePerShare = pool.accGRupeePerShare.add(GRUPEEReward.mul(1e12).div(sharesTotal));
        pool.lastRewardBlock = block.number;
    }

    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.shares > 0) {
            uint256 pending = user.shares.mul(pool.accGRupeePerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeGRUPEETransfer(msg.sender, pending);
            }
        }

        if (_amount > 0) {
            pool.want.safeTransferFrom(address(msg.sender), address(this), _amount);
            pool.want.safeIncreaseAllowance(pool.strategy, _amount);
            uint256 sharesAdded = IStrategy(poolInfo[_pid].strategy).deposit(msg.sender, _amount);
            user.shares = user.shares.add(sharesAdded);
        }

        user.rewardDebt = user.shares.mul(pool.accGRupeePerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        updatePool(_pid);

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 wantLockedTotal = IStrategy(poolInfo[_pid].strategy).wantLockedTotal();
        uint256 sharesTotal = IStrategy(poolInfo[_pid].strategy).sharesTotal();

        require(user.shares > 0, "User Share is 0");
        require(sharesTotal > 0, "User Share is 0");

        // Golden Rupee withdrawal
        uint256 pending = user.shares.mul(pool.accGRupeePerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safeGRUPEETransfer(msg.sender, pending);
        }

        // Token staked withdrawal
        uint256 amount = user.shares.mul(wantLockedTotal).div(sharesTotal);
        if (_amount > amount) {
            _amount = amount;
        }

        if (_amount > 0) {
            uint256 sharesRemoved = IStrategy(poolInfo[_pid].strategy).withdraw(msg.sender, _amount);

            if (sharesRemoved > user.shares) {
                user.shares = 0;
            } else {
                user.shares = user.shares.sub(sharesRemoved);
            }

            uint256 wantBalance = IBEP20(pool.want).balanceOf(address(this));
            if (wantBalance < _amount) {
                _amount = wantBalance;
            }
            pool.want.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.shares.mul(pool.accGRupeePerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function withdrawAll(uint256 _pid) public nonReentrant {
        withdraw(_pid, uint256(-1));
    }

    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 wantLockedTotal = IStrategy(poolInfo[_pid].strategy).wantLockedTotal();
        uint256 sharesTotal = IStrategy(poolInfo[_pid].strategy).sharesTotal();
        uint256 amount = user.shares.mul(wantLockedTotal).div(sharesTotal);

        IStrategy(poolInfo[_pid].strategy).withdraw(msg.sender, amount);

        user.shares = 0;
        user.rewardDebt = 0;
        pool.want.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    function safeGRUPEETransfer(address _to, uint256 _amount) internal {
        uint256 balance = IBEP20(GRUPEE).balanceOf(address(this));
        if (_amount > balance) {
            IBEP20(GRUPEE).transfer(_to, balance);
        } else {
            IBEP20(GRUPEE).transfer(_to, _amount);
        }
    }

    function inCaseTokensGetStuck(address _token, uint256 _amount) public onlyOwner {
        require(_token != GRUPEE, "!safe");
        IBEP20(_token).safeTransfer(msg.sender, _amount);
    }
}
