// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;


import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


contract Staking is Ownable{
    using SafeMath for uint256;

    address public byzToken;
    address public shdwAddress;

    uint256 public depositTime;    
    uint256 public lastRewardTime;

    uint256 public accPerShare;
    uint256 public rewardMultiplier;

    uint256 public period;
    uint256 public slowPeriod;

    uint256 public totalStaker;
    uint256 public distributedETH;
    uint256 public distributedSHDW;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt; 
        uint256 lastTime;
    }


    mapping (address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event DepositFunds(uint256 ethAmount, uint256 shdwAmount);
    event Withdraw(address indexed user);

    constructor (address _byzAddress) {
        byzToken = _byzAddress;
        shdwAddress = 0xddBa66C1eBA873e26Ac0215Ca44892a07d83aDF5;
        period = 6 hours;
        slowPeriod = 12 hours;
    } 

    receive() external payable {}

    // Deposit bYZ tokens to the pool
    function deposit(uint256 _amount) external {

        UserInfo storage user = userInfo[msg.sender];
        require(block.timestamp - user.lastTime > slowPeriod, "Slow Mode");

        updatePool();

        bool flag;

        (uint256 etherBalance, uint256 shdwBalance) = getVaultBalance();
        if (user.amount > 0) {
            flag = true;
            uint256 pending = user.amount.mul(accPerShare).div(1e18).sub(user.rewardDebt);
            uint256 shdwPending = pending * shdwBalance / etherBalance;
            if(pending > 0) {
                distributedETH += pending;
                distributedSHDW += shdwPending;
                payable(msg.sender).transfer(pending);
                IERC20(shdwAddress).transfer(msg.sender, shdwPending);
            }
            user.lastTime = block.timestamp;
        }

        if (_amount > 0) {
            if (!flag) totalStaker++;
            IERC20(byzToken).transferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(accPerShare).div(1e18);
        emit Deposit(msg.sender, _amount);
    }

    function claimable(address claimer) external view returns(bool) {
        UserInfo storage user = userInfo[claimer];
        bool result = block.timestamp - user.lastTime > slowPeriod;
        return result;
    }
    
    function withdraw() external {
        UserInfo storage user = userInfo[msg.sender];
        IERC20(byzToken).transfer(msg.sender, user.amount);

        delete userInfo[msg.sender];

        emit Withdraw(msg.sender);
    }

    function setSHDWAddress(address _shdwAddress) external onlyOwner {
        require(
            _shdwAddress != address(0),
            "Shadow address should be non-zero address"
        );
        shdwAddress = _shdwAddress;
    }
    
    function setByzAddress(address _byzAddress) external onlyOwner {
        require(
            _byzAddress != address(0),
            "BYZ address should be non-zero address"
        );
        byzToken = _byzAddress;
    }
    
    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(rewardMultiplier);
    }

    function getVaultBalance() public view returns (uint256, uint256) {
        uint256 etherBalance = address(this).balance;
        uint256 shdwAmount = IERC20(shdwAddress).balanceOf(address(this));

        return (etherBalance, shdwAmount);
    }

    // View function to see pending rewards on frontend.
    function pendingReward(address _user) external view returns (uint256, uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 totalSupply = IERC20(byzToken).balanceOf(address(this));
        uint256 accPerShare_ = accPerShare;
        uint256 timestamp = block.timestamp / period * period;
        if (timestamp > lastRewardTime && totalSupply != 0) {
            uint256 multiplier = getMultiplier(lastRewardTime, timestamp);
            accPerShare_ = accPerShare_.add(multiplier.mul(1e18).div(totalSupply));
        }
        uint256 etherReward = user.amount.mul(accPerShare_).div(1e18).sub(user.rewardDebt);
        (uint256 etherBalance, uint256 shdwBalance) = getVaultBalance();
        uint256 shdwReward = etherReward * shdwBalance / etherBalance;

        return (etherReward, shdwReward);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool() public {
        if (block.timestamp <= lastRewardTime) {
            return;
        }

        uint256 totalSupply = IERC20(byzToken).balanceOf(address(this));
        
        if (totalSupply == 0) {
            lastRewardTime = block.timestamp;
            return;
        }
        uint256 timestamp = block.timestamp / period * period;

        uint256 multiplier = getMultiplier(lastRewardTime, timestamp);
    
        accPerShare = accPerShare.add(multiplier.mul(1e18).div(totalSupply));
        lastRewardTime = timestamp;
    }

    function setPeriod(uint256 _newPeriod) external onlyOwner {
        require(_newPeriod <= 6 hours, "Exceed the Period Limit");
        period = _newPeriod;
    }

    function setSlowPeriod(uint256 _newSlowPeriod) external onlyOwner {
        require(_newSlowPeriod <= 12 hours, "Exceed the Slow Period Limit");
        slowPeriod = _newSlowPeriod;
    }

    function depositFunds(uint256 shdwAmount) external payable onlyOwner{
        require(depositTime == 0 || (depositTime + 1 weeks < block.timestamp && depositTime + 1 weeks + 1 days > block.timestamp), "Invalid Deposit Time");
        rewardMultiplier = msg.value / 1 weeks;
        depositTime = block.timestamp;
        IERC20(shdwAddress).transferFrom(msg.sender, address(this), shdwAmount);
        emit DepositFunds(msg.value, shdwAmount);
    }

}