// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IBarRewarder {
    function claimReward() external;
}

// JoeBar is the coolest bar in town. You come in with some Joe, and leave with more! The longer you stay, the more Joe you get.
//
// This contract handles swapping to and from moJoe, JoeSwap's staking token.
contract JoeBarV2 is Initializable, ERC20Upgradeable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    IERC20Upgradeable public joe;
    IBarRewarder public rewarder;
    uint256 public entryFee;

    event SetEntryFee(uint256 _entryFee);
    event SetRewarder(address _rewarder);

    function initialize(IERC20Upgradeable _joe, uint256 _entryFee) public initializer {
        __ERC20_init("JoeBarV2", "moJOE");
        __Ownable_init();

        joe = _joe;
        setEntryFee(_entryFee);
    }

    // Enter the bar. Pay some JOEs. Earn some shares.
    // Locks Joe and mints moJoe
    function enter(uint256 _amount) external {
        // Gets the rewards
        rewarder.claimReward();

        uint256 fee = _amount.mul(entryFee).div(10000);
        uint256 amount = _amount.sub(fee);

        // Gets the amount of Joe locked in the contract
        uint256 totalJoe = joe.balanceOf(address(this));
        // Gets the amount of moJoe in existence
        uint256 totalShares = totalSupply();
        // If no moJoe exists, mint it 1:1 to the amount (minus the fees) put in
        if (totalShares == 0 || totalJoe == 0) {
            require(_amount >= 1e18, "JoeBarV2: You need to enter with at least 1 $JOE.");
            _mint(msg.sender, amount);
        }
        // Calculate and mint the amount of moJoe the Joe is worth. The ratio will change overtime, as moJoe is
        // burned/minted and Joe deposited + gained from fees / withdrawn.
        else {
            uint256 what = amount.mul(totalShares).div(totalJoe);
            _mint(msg.sender, what);
        }
        // Lock the Joe in the contract
        joe.transferFrom(msg.sender, address(this), amount);
        joe.transferFrom(msg.sender, address(rewarder), fee);
    }

    // Leave the bar. Claim back your JOEs.
    // Unlocks the staked + gained Joe and burns moJoe
    function leave(uint256 _share) external {
        // Gets the rewards
        rewarder.claimReward();

        // Gets the amount of moJoe in existence
        uint256 totalShares = totalSupply();
        // Calculates the amount of Joe the moJoe is worth
        uint256 what = _share.mul(joe.balanceOf(address(this))).div(totalShares);
        _burn(msg.sender, _share);
        joe.transfer(msg.sender, what);
    }

    // Set the entryFee for moJoe.
    function setEntryFee(uint256 _entryFee) public onlyOwner {
        require(_entryFee <= 5000, "JoeBarV2: entryFee too high");
        entryFee = _entryFee;

        emit SetEntryFee(_entryFee);
    }

    function setRewarder(IBarRewarder _rewarder) external onlyOwner {
        rewarder = _rewarder;

        emit SetRewarder(address(_rewarder));
    }
}

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./JoeToken.sol";

// MasterChefJoe is a boss. He says "go f your blocks lego boy, I'm gonna use timestamp instead".
// And to top it off, it takes no risks. Because the biggest risk is operator error.
// So we make it virtually impossible for the operator of this contract to cause a bug with people's harvests.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once JOE is sufficiently
// distributed and the community can show to govern itself.
//
// With thanks to the Lydia Finance team.
//
// Godspeed and may the 10x be with you.
contract StableJoeStaking is Ownable, ERC20 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of JOEs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accJoePerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accJoePerShare` (and `lastRewardTimestamp`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. JOEs to distribute per second.
        uint256 lastRewardTimestamp; // Last timestamp that JOEs distribution occurs.
        uint256 accJoePerShare; // Accumulated JOEs per share, times 1e12. See below.
    }

    // The TOKEN!
    IERC20 public token;

    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    event Add(address indexed lpToken, uint256 allocPoint);
    event Set(uint256 indexed pid, uint256 allocPoint);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdateEmissionRate(address indexed user, uint256 _joePerSec);

    constructor(
        IERC20 _token
    ) public {
        token = _token;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken) public onlyOwner {
        require(!isPool[_lpToken], "add: LP already added");
        massUpdatePools();
        uint256 lastRewardTimestamp = block.timestamp > startTimestamp ? block.timestamp : startTimestamp;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
        lpToken: _lpToken,
        allocPoint: _allocPoint,
        lastRewardTimestamp: lastRewardTimestamp,
        accJoePerShare: 0
        })
        );
        isPool[_lpToken] = true;
        emit Add(address(_lpToken), _allocPoint);
    }

    // Update the given pool's JOE allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint) public onlyOwner {
        massUpdatePools();
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        emit Set(_pid, _allocPoint);
    }

    // View function to see pending JOEs on frontend.
    function pendingJoe(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accJoePerShare = pool.accJoePerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 multiplier = block.timestamp.sub(pool.lastRewardTimestamp);
            uint256 joeReward = multiplier
            .mul(joePerSec)
            .mul(pool.allocPoint)
            .div(totalAllocPoint)
            .mul(1000 - devPercent - treasuryPercent)
            .div(1000);
            accJoePerShare = accJoePerShare.add(joeReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accJoePerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTimestamp) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardTimestamp = block.timestamp;
            return;
        }
        uint256 multiplier = block.timestamp.sub(pool.lastRewardTimestamp);
        uint256 joeReward = multiplier.mul(joePerSec).mul(pool.allocPoint).div(totalAllocPoint);
        uint256 lpPercent = 1000 - devPercent - treasuryPercent;
        joe.mint(devaddr, joeReward.mul(devPercent).div(1000));
        joe.mint(treasuryaddr, joeReward.mul(treasuryPercent).div(1000));
        joe.mint(address(this), joeReward.mul(lpPercent).div(1000));
        pool.accJoePerShare = pool.accJoePerShare.add(joeReward.mul(1e12).div(lpSupply).mul(lpPercent).div(1000));
        pool.lastRewardTimestamp = block.timestamp;
    }

    // Deposit LP tokens to MasterChef for JOE allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accJoePerShare).div(1e12).sub(user.rewardDebt);
            safeJoeTransfer(msg.sender, pending);
        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accJoePerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accJoePerShare).div(1e12).sub(user.rewardDebt);
        safeJoeTransfer(msg.sender, pending);
        user.amount = user.amount.sub(_amount);
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        user.rewardDebt = user.amount.mul(pool.accJoePerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe joe transfer function, just in case if rounding error causes pool to not have enough JOEs.
    function safeJoeTransfer(address _to, uint256 _amount) internal {
        uint256 joeBal = joe.balanceOf(address(this));
        if (_amount > joeBal) {
            joe.transfer(_to, joeBal);
        } else {
            joe.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
        emit SetDevAddress(msg.sender, _devaddr);
    }

    function setDevPercent(uint256 _newDevPercent) public onlyOwner {
        require(0 <= _newDevPercent && _newDevPercent <= 1000, "setDevPercent: invalid percent value");
        require(treasuryPercent + _newDevPercent <= 1000, "setDevPercent: total percent over max");
        devPercent = _newDevPercent;
    }

    function setTreasuryPercent(uint256 _newTreasuryPercent) public onlyOwner {
        require(0 <= _newTreasuryPercent && _newTreasuryPercent <= 1000, "setTreasuryPercent: invalid percent value");
        require(devPercent + _newTreasuryPercent <= 1000, "setTreasuryPercent: total percent over max");
        treasuryPercent = _newTreasuryPercent;
    }

    // Pancake has to add hidden dummy pools inorder to alter the emission,
    // here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _joePerSec) public onlyOwner {
        massUpdatePools();
        joePerSec = _joePerSec;
        emit UpdateEmissionRate(msg.sender, _joePerSec);
    }
}
