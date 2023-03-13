// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "https://github.com/Uniswap/v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol";
import "https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Factory.sol";
import "https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Pair.sol";


contract bYieldzToken is ERC20, Ownable {
    using SafeMath for uint256;
    
    // Definition of variables
    address public yzToken;
    address public treasury = 0x3D27f909606c97b13973c52b0752c06C5cAd9240;
    address public shdwAddress;
    
    uint256 public rateForTwo;
    uint256 public rateForFour;

    uint256 public period;
    uint256 public lockedYZAmount;

    uint256 public slowPeriod;

    IUniswapV2Router02 public uniswapV2Router = IUniswapV2Router02(0xCCED48E6fe655E5F28e8C4e56514276ba8b34C09);

    // Definition of main struct data 
    struct StakeData  {
        address staker;
        uint256 stakeTime;
        uint256 lockTime;
        uint256 amount;
        uint256 rate;
    }

    mapping (address => StakeData[]) public userData;

    bool private swapping;

    event Stake(address indexed account, uint256 amount, uint256 period, uint256 stakeTime);
    event Claim(address indexed account, uint256 count);
    event Withdraw(address indexed account, uint256 count);
 
    constructor(address _yieldToken) ERC20("TestbYieldz", "tbYZ") {
        yzToken = _yieldToken;
        shdwAddress = 0xddBa66C1eBA873e26Ac0215Ca44892a07d83aDF5;
        period = 6 hours;
    }

    /**
    * Stake function 
    * @param amount: stake amount to set
    * @param lockPeriod: the lock period as 20 days and 40 days
    */
    function stake(uint256 amount, uint256 lockPeriod) external  {

        require(lockPeriod == 20 || lockPeriod == 40, "Not Lock Period Available");

        uint256 _rate;

        if (lockPeriod == 20) _rate = rateForTwo;
        else _rate = rateForFour;

        userData[msg.sender].push(StakeData ({
            staker: msg.sender,
            stakeTime: block.timestamp,
            lockTime: lockPeriod * 4 * period  + block.timestamp,
            amount: amount,
            rate: _rate 
        }));

        IERC20(yzToken).transferFrom(msg.sender, address(this), amount);

        lockedYZAmount += amount;
        
        emit Stake(msg.sender, amount, lockPeriod, block.timestamp);
    }

    /**
    * Withdraw function
    * The staker can withdraw the reward from the stake pool
    */
    function withdraw(uint256 count) external {
        StakeData storage data = userData[msg.sender][count];
        uint256 lastIndex = userData[msg.sender].length - 1;

        uint256 byzAmount = getReward(msg.sender, count);
        uint256 yzAmount = data.amount ;
        uint256 yzRemainAmount;

        if (block.timestamp < data.lockTime) {
            uint256 _preWithdrawPercent = getPreWithdrawPercent(msg.sender, count);
            yzRemainAmount = yzAmount * _preWithdrawPercent / 1000;
            yzAmount = yzAmount - yzRemainAmount;
        }

        if (yzRemainAmount > 0) {
            swapTokensForEth(yzRemainAmount);
            uint256 newBalance = address(this).balance;
            payable(treasury).transfer(newBalance);
        }

        IERC20(yzToken).transfer(msg.sender, yzAmount);

        lockedYZAmount = lockedYZAmount.sub(yzAmount);
      
        _mint(msg.sender, byzAmount);
        
        userData[msg.sender][count] = userData[msg.sender][lastIndex];
        userData[msg.sender].pop();

        emit Withdraw(msg.sender, count);

    }

    function claimable(address staker, uint256 _count) external view returns(bool) {
        StakeData storage data = userData[staker][_count];
        bool result = block.timestamp - data.stakeTime > slowPeriod;
        return result;
    }

    function getPreWithdrawPercent(address staker, uint256 _count) public view returns(uint256) {
        StakeData storage data = userData[staker][_count];
        uint256 delta = data.lockTime - block.timestamp;
        uint256 _period;
        if (data.rate == rateForTwo) _period = 20;
        else _period = 40; 
        uint256 _preWithdrawPercent = delta /(period * 4) * 250 / _period + 50;
        return _preWithdrawPercent;
    }
    /**
    * Withdraw function
    * The staker can withdraw the reward from the stake pool
    */
    function claim(uint256 count) external {
        StakeData storage data = userData[msg.sender][count];
        require(block.timestamp - data.stakeTime > slowPeriod, "Slow Mode");

        uint256 byzAmount = getReward(msg.sender, count);

        _mint(msg.sender, byzAmount);
        
        if (block.timestamp >= data.lockTime) data.stakeTime = data.lockTime;
        else data.stakeTime = block.timestamp;

        emit Claim(msg.sender, count);
    }
    receive() external payable {}
    /**
    * Get reward amount of staker
    * @param receiver the receiver address of the staker
    */
    function getReward(address receiver, uint256 count) public view returns(uint256) {
        StakeData storage data = userData[receiver][count];

        if (data.lockTime == 0) return 0;
        uint256 reward;
        if (block.timestamp >= data.lockTime) {
            reward = (data.lockTime - data.stakeTime) / period * data.amount * data.rate / 1000 * period / 1 days;
        } else {
            reward = (block.timestamp - data.stakeTime) / period * data.amount * data.rate / 1000 * period / 1 days;
        }

        return reward;

    }

    function swapTokensForEth(uint256 tokenAmount) private {
        swapping = true;

        address[] memory path = new address[](3);
        path[0] = yzToken;
        path[1] = shdwAddress;
        path[2] = uniswapV2Router.WETH();

        IERC20(yzToken).approve(address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
        swapping = false;
    }

    function setYZAddress(address _yzAddress) external onlyOwner {
        require(
            _yzAddress != address(0),
            "YZ address should be non-zero address"
        );
        yzToken = _yzAddress;
    }

    function setSlowPeriod(uint256 _newSlowPeriod) external onlyOwner {
        slowPeriod = _newSlowPeriod;
    }

   
    // Get Rate of the individual lock period
    function getRate() external view returns(uint256, uint256) {
        return (rateForTwo, rateForFour);
    }

    // Set Rate of the individual lock period
    function setRate(uint256 _newTwoRate, uint256 _newFourRate) external onlyOwner{
        rateForTwo = _newTwoRate;
        rateForFour = _newFourRate;
    }

    // Set the reward getting period
    function setPeriod(uint256 _newPeriod) external onlyOwner{
        period = _newPeriod;
    }

    // Set the reward getting period
    function setDefaultPeriod() external onlyOwner{
        period = 6 hours;
        slowPeriod = 12 hours;
    }


    function setShdwAddress(address _newAddr) external onlyOwner {
        shdwAddress = _newAddr;
    }
   
}