// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "https://github.com/Uniswap/v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol";
import "https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Factory.sol";
import "https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Pair.sol";

contract YieldzToken is ERC20, Ownable {
    using SafeMath for uint256;

    address public treasury;
    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    address public shdwAddress = 0xddBa66C1eBA873e26Ac0215Ca44892a07d83aDF5;

    uint256 public buyFee;
    uint256 public sellFee;
    uint256 public p2pFee;

    uint256 public tenBondPrice;
    uint256 public twentyBondPrice;
    
    uint256 public tenBondTotal;
    uint256 public twentyBondTotal;

    uint256 public slowPeriod;
    
    // Definition of main struct data 
    struct BondData  {
        uint256 startTime;
        uint256 endTime;
        uint256 period;
        uint256 rate;
    }
    
    bool private swapping;
    

    mapping (address => BondData[]) public userBond;
    mapping (address => bool) private _isExcludedFromFees;
    mapping (address => bool) public automatedMarketMakerPairs;

    event CreateBond(address indexed account, uint256 period);
    event ClaimBond(address indexed account, uint256 reward);
    event RemoveBond(address indexed account, uint256 count);
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event SetTreasury(address treasury);
    event SetFees(uint256 buyFee, uint256 sellFee, uint256 p2pFee);
    event SetBondTotal(uint256 tenBondTotal, uint256 twentyBondTotal);
    event SetBondPrice(uint256 tenBondPrice, uint256 twentyBondPrice);

    constructor(address _treasury, uint256 _buyFee, uint256 _sellFee, uint256 _p2pFee) ERC20("TestYieldz", "tYZ") {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0xCCED48E6fe655E5F28e8C4e56514276ba8b34C09);
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), shdwAddress);

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        treasury = _treasury;
        buyFee = _buyFee;
        sellFee = _sellFee;
        p2pFee = _p2pFee;

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);

        _mint(msg.sender, 1 * 10**25);

        excludeFromFees(owner(), true);
        excludeFromFees(treasury, true);
    }

    receive() external payable {}

   
    function createBond(uint256 period) external payable {

        require(period == 10 || period == 20, "Not Exact Bond");
        
        uint rate_;

        if (period == 10) {
            rate_ = tenBondTotal * 10**18 / tenBondPrice / 10 days;
            require(msg.value == tenBondTotal, "The bond price limited");
            payable(treasury).transfer(tenBondTotal);
        } else {
            rate_ = twentyBondTotal * 10**18  / twentyBondPrice / 20 days;
            require(msg.value == twentyBondTotal, "The bond price limited");
            payable(treasury).transfer(twentyBondTotal);
        }

        userBond[msg.sender].push(BondData ({
            startTime: block.timestamp,
            endTime: block.timestamp + period * 1 days,
            period: period,
            rate: rate_ 
        }));
        emit CreateBond(msg.sender, period);
    }

    function claimBond(uint256 _count) external {
        BondData storage bond = userBond[msg.sender][_count];

        require(block.timestamp - bond.startTime > slowPeriod, "Slow mode");
        require(bond.endTime > bond.startTime, "Finished Bond");
        
        uint256 reward;

        if (block.timestamp >= bond.endTime) {
            reward = (bond.endTime - bond.startTime) * bond.rate;
            removeBond(msg.sender, _count);
        } else {
            reward = (block.timestamp - bond.startTime) * bond.rate;
            bond.startTime = block.timestamp;
        }

        _mint(msg.sender, reward);

        emit ClaimBond(msg.sender, reward);
    }

    function claimable(address bonder, uint256 _count) external view returns(bool) {
        BondData memory bond = userBond[bonder][_count];
        bool result = block.timestamp - bond.startTime > slowPeriod;
        return result;
    }
    
    function removeBond(address userAddres, uint256 count) internal {
        uint256 lastIndex = userBond[userAddres].length - 1;
        userBond[userAddres][count] = userBond[userAddres][lastIndex];

        userBond[userAddres].pop();
        emit RemoveBond(msg.sender, count);
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(_isExcludedFromFees[account] != excluded, "error: Account is already the value of 'excluded'");
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) public onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFees[accounts[i]] = excluded;
        }

        emit ExcludeMultipleAccountsFromFees(accounts, excluded);
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != uniswapV2Pair, "error: The Uniswap pair cannot be removed from automatedMarketMakerPairs");

        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, "error: Automated market maker pair is already set to that value");
        automatedMarketMakerPairs[pair] = value;

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function setTreasuryAddress(address _treasury) public onlyOwner {
        require(
            _treasury != address(0),
            "Treasury address should be non-zero address"
        );
        treasury = _treasury;
        emit SetTreasury(treasury);
    }

    function setFees(uint256 _buyFee, uint256 _sellFee, uint256 _p2pFee) public onlyOwner {
        require(
            _buyFee <= 25 &&
            _sellFee <= 25 &&
            _p2pFee <= 25,
            "The Fee should be smaller than 25"
        );
        buyFee = _buyFee;
        sellFee = _sellFee;
        p2pFee = _p2pFee;
        emit SetFees(buyFee, sellFee, p2pFee);
    }

    function _transfer(address from, address to, uint256 amount)
        internal 
        override
    {
        if(!(_isExcludedFromFees[from] || _isExcludedFromFees[to] || swapping)) {
            uint256 fee;
            bool inBuying;

            if(automatedMarketMakerPairs[to]){
        	    fee = amount.mul(sellFee).div(100);
        	}
            else if(automatedMarketMakerPairs[from]){
        	    fee = amount.mul(buyFee).div(100);
                inBuying = true;
        	}
            else {
                fee = amount.mul(p2pFee).div(100);
            }
            amount -= fee;

            if (inBuying) super._transfer(from, treasury, fee);
            else {
                super._transfer(from, address(this), fee);
                swapTokensForShdw(fee);
            }
        }
        
        super._transfer(from, to, amount);
        
    }
    
    function swapTokensForShdw(uint256 tokenAmount) private {
        swapping = true;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = shdwAddress;

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            treasury,
            block.timestamp
        );
       
        swapping = false;
    }

    function isExcludedFromFees(address account) public view returns(bool) {
        return _isExcludedFromFees[account];
    }
    
    function setBondTotal(uint256 _tenBondTotal, uint256 _twentyBondTotal) external onlyOwner {
        tenBondTotal = _tenBondTotal;
        twentyBondTotal = _twentyBondTotal;

        emit SetBondTotal(_tenBondTotal, _twentyBondTotal);
    }

    function setBondPrice(uint256 _tenBondPrice, uint256 _twentyBondPrice) external onlyOwner {
        tenBondPrice = _tenBondPrice;
        twentyBondPrice = _twentyBondPrice;

        emit SetBondPrice(_tenBondPrice, _twentyBondPrice);
    }

    function setSlowPeriod(uint256 _newSlowPeriod) external onlyOwner {
        require(_newSlowPeriod <= 12 hours, "Exceed the Slow Period Limit");
        slowPeriod = _newSlowPeriod;
    }

    function setShdwAddress(address _newAddr) external onlyOwner {
        require(
            _newAddr != address(0),
            "Invalid to set the new shadow address"
        );
        shdwAddress = _newAddr;
    }
}
