// SPDX-License-Identifier: MIT

/* 

        ██████╗  █████╗ ██╗   ██╗██╗    ██╗ █████╗ ██╗   ██╗
        ██╔══██╗██╔══██╗╚██╗ ██╔╝██║    ██║██╔══██╗╚██╗ ██╔╝
        ██████╔╝███████║ ╚████╔╝ ██║ █╗ ██║███████║ ╚████╔╝ 
        ██╔═══╝ ██╔══██║  ╚██╔╝  ██║███╗██║██╔══██║  ╚██╔╝  
        ██║     ██║  ██║   ██║   ╚███╔███╔╝██║  ██║   ██║   
        ╚═╝     ╚═╝  ╚═╝   ╚═╝    ╚══╝╚══╝ ╚═╝  ╚═╝   ╚═╝   
        PayWay - Pay the Way you Want


    Website     :  https://payway.finance
    Whitepaper  :  https://docs.payway.finance

    Telegram    :  https://t.me/payway_eth
    Twitter (X) :  https://x.com/payway_eth

    Medium      :  https://medium.com/@payway
    Linktr      :  https://linktr.ee/PayWayOfficial


    Audit (InterFi) : Audit.payway.finance

*/

pragma solidity 0.8.20;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {return msg.sender;}
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }
    function owner() public view returns (address) {return _owner;}
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external;
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(address token, uint amountTokenDesired, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

contract PAYWAY is Context , IERC20, Ownable {
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isExcludedFromFee;
    address payable private _taxWallet;
    address private constant deadAddress = address(0xdead);

    uint256 private _startingBuyTax=25;
    uint256 private _startingSellTax=27;
    uint256 private _endingBuyTax=10;
    uint256 private _endingSellTax=25;
    uint256 private _reduceBuyTaxThreshold=30;
    uint256 private _reduceSellTaxThreshold=45;
    uint256 private _swapPreventionThreshold=40;
    uint256 private _buyTransactionCount=0;

    uint8 private constant _decimals = 9;
    uint256 private constant _tTotal = 10000000 * 10**_decimals;
    string private constant _name = unicode"PAYWAY";
    string private constant _symbol = unicode"$PAY";
    uint256 public _maxTxAmount = 100000 * 10**_decimals;
    uint256 public _maxWalletSize = 100000 * 10**_decimals;
    uint256 public _taxSwapThreshold= 10000 * 10**_decimals;
    uint256 public _maxTaxSwap= 100000 * 10**_decimals;

    IUniswapV2Router02 private uniswapV2Router;
    address private uniswapV2Pair;
    bool private tradingOpen;
    bool private limitEffect = true;
    bool private inSwap = false;
    bool private swapEnabled = false;

    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor(address payable taxWalletAddress) {
        _taxWallet = taxWalletAddress;
        _balances[_msgSender()] = _tTotal;
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[deadAddress]= true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[_taxWallet] = true;
        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public pure override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()] - amount);
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 taxAmount = 0;
        if (from != owner() && to != owner()) { 
            if (!tradingOpen) {
                require(
                    _isExcludedFromFee[from] || _isExcludedFromFee[to],
                    "Trading is not open yet"
                );
            }
            if (from == uniswapV2Pair && to != address(uniswapV2Router) && !_isExcludedFromFee[to]) {
                if (limitEffect) {
                    require(amount <= _maxTxAmount, "Exceeds the _maxTxAmount.");
                    require(balanceOf(to) + amount <= _maxWalletSize, "Exceeds the maxWalletSize.");
                } 
                _buyTransactionCount++;
            }
            if (to == uniswapV2Pair && from != address(this)) {
                taxAmount = amount * 
                    ((_buyTransactionCount > _reduceSellTaxThreshold)
                        ? _endingSellTax : _startingSellTax) / 100;
            } else if (from == uniswapV2Pair && to != address(this)) {
                taxAmount = amount * 
                    ((_buyTransactionCount > _reduceBuyTaxThreshold)
                        ? _endingBuyTax : _startingBuyTax) / 100;
            }
            uint256 contractTokenBalance = balanceOf(address(this));
            if (
                !inSwap && 
                to == uniswapV2Pair && 
                swapEnabled && 
                contractTokenBalance > _taxSwapThreshold && 
                _buyTransactionCount > _swapPreventionThreshold
            ){
                swapTokensForEth(min(amount, min(contractTokenBalance, _maxTaxSwap)));
                uint256 contractETHBalance = address(this).balance;
                if (contractETHBalance > 0) {
                    sendETHToFee(address(this).balance);
                }
            }
        }
        if (taxAmount > 0) {
            _balances[address(this)] += taxAmount;
            emit Transfer(from, address(this), taxAmount);
        }
        _balances[from] -= amount;
        _balances[to] += (amount - taxAmount);
        emit Transfer(from, to, amount - taxAmount);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }


    function sendETHToFee(uint256 amount) private {
        _taxWallet.transfer(amount);
    }

    function swapTokensForEth(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function createPair() external onlyOwner() {
        require(!tradingOpen,"Liquidity is already added");
        uint256 tokenAmount = balanceOf(address(this)) - (_tTotal * _startingBuyTax / 100);
        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), address(uniswapV2Router), _tTotal);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
            address(this), 
            uniswapV2Router.WETH()
        );
        uniswapV2Router.addLiquidityETH{value: address(this).balance} (
            address(this),
            tokenAmount,
            0,
            0,
            owner(),
            block.timestamp
        );
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max); 
    }

    function removeLimits () external onlyOwner returns (bool){
        limitEffect = false;
        return true;
    }
    
    function setBuyTax(uint256 _newBuyTax) external onlyOwner returns (bool) {
        _endingBuyTax = _newBuyTax;
        require(_newBuyTax <= 5, "Buy tax cannot exceed 5");
        return true;
    }

    function setSellTax(uint256 _newSellTax) external onlyOwner returns (bool) {
        _endingSellTax = _newSellTax;
        require(_newSellTax <= 5, "Sell tax cannot exceed 5");
        return true;
    }

    function openTrading() external onlyOwner returns (bool) {
        require(!tradingOpen,"Trading is already open");
        swapEnabled = true;
        tradingOpen = true;
        return true;
    }

    function clearStuckETH() external onlyOwner returns (bool) {
        require(tradingOpen, "Trading is not open yet");
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            _taxWallet.transfer(ethBalance);
        }
        return true;
    }
    receive() external payable {}
}