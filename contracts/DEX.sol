// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.8.0/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.8.0/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.8.0/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.8.0/contracts/token/ERC20/IERC20.sol";

contract DEX is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public token1;
    IERC20 public token2;

    uint256 public token1Balance;
    uint256 public token2Balance;

    struct Trade {
        address user;
        string operation;
        address tokenIn;
        uint256 amountIn;
        address tokenOut;
        uint256 amountOut;
        uint256 timestamp;
    }

    Trade[] public trades; // 存储交易记录

    event LiquidityAdded(address indexed provider, uint256 token1Amount, uint256 token2Amount);
    event LiquidityRemoved(address indexed provider, uint256 token1Amount, uint256 token2Amount);
    event Swap(address indexed user, address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);

    constructor(address _token1, address _token2) Ownable() {
        require(_token1 != address(0) && _token2 != address(0), "Invalid token addresses");
        token1 = IERC20(_token1);
        token2 = IERC20(_token2);
        _transferOwnership(msg.sender);
    }

    function addLiquidity(uint256 _token1Amount, uint256 _token2Amount) external nonReentrant {
        require(_token1Amount > 0 && _token2Amount > 0, "Amounts must be greater than 0");

        uint256 allowance1 = token1.allowance(msg.sender, address(this));
        uint256 allowance2 = token2.allowance(msg.sender, address(this));
        require(allowance1 >= _token1Amount, "Insufficient token1 allowance");
        require(allowance2 >= _token2Amount, "Insufficient token2 allowance");

        uint256 balance1 = token1.balanceOf(msg.sender);
        uint256 balance2 = token2.balanceOf(msg.sender);
        require(balance1 >= _token1Amount, "Insufficient token1 balance");
        require(balance2 >= _token2Amount, "Insufficient token2 balance");

        token1.safeTransferFrom(msg.sender, address(this), _token1Amount);
        token2.safeTransferFrom(msg.sender, address(this), _token2Amount);

        token1Balance += _token1Amount;
        token2Balance += _token2Amount;

        // 记录添加流动性操作
        trades.push(Trade({
            user: msg.sender,
            operation: "AddLiquidity",
            tokenIn: address(0), // 不适用
            amountIn: _token1Amount + _token2Amount,
            tokenOut: address(0), // 不适用
            amountOut: 0,
            timestamp: block.timestamp
        }));

        emit LiquidityAdded(msg.sender, _token1Amount, _token2Amount);
    }

    function addSingleLiquidity(address token, uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(token == address(token1) || token == address(token2), "Invalid token address");

        IERC20 selectedToken = token == address(token1) ? token1 : token2;
        uint256 selectedBalance = selectedToken.balanceOf(msg.sender);
        uint256 selectedAllowance = selectedToken.allowance(msg.sender, address(this));

        require(selectedAllowance >= amount, "Insufficient token allowance");
        require(selectedBalance >= amount, "Insufficient token balance");

        selectedToken.safeTransferFrom(msg.sender, address(this), amount);

        // 记录添加单个流动性操作
        trades.push(Trade({
            user: msg.sender,
            operation: "AddSingleLiquidity",
            tokenIn: address(0),// 不适用
            amountIn: amount,
            tokenOut: address(0),// 不适用
            amountOut: 0,
            timestamp: block.timestamp
        }));

        if (token == address(token1)) {
            token1Balance += amount;
            emit LiquidityAdded(msg.sender, amount, 0);
        } else {
            token2Balance += amount;
            emit LiquidityAdded(msg.sender, 0, amount);
        }
    }


    function removeLiquidity(uint256 _token1Amount, uint256 _token2Amount) external onlyOwner nonReentrant {
        require(_token1Amount > 0 && _token2Amount > 0, "Amounts must be greater than 0");
        require(token1Balance >= _token1Amount && token2Balance >= _token2Amount, "Insufficient liquidity");

        token1Balance -= _token1Amount;
        token2Balance -= _token2Amount;

        token1.safeTransfer(owner(), _token1Amount);
        token2.safeTransfer(owner(), _token2Amount);

        // 记录移除流动性操作
        trades.push(Trade({
            user: msg.sender,
            operation: "RemoveLiquidity",
            tokenIn: address(0), // 不适用
            amountIn: _token1Amount + _token2Amount,
            tokenOut: address(0), // 不适用
            amountOut: 0,
            timestamp: block.timestamp
        }));

        emit LiquidityRemoved(owner(), _token1Amount, _token2Amount);
    }

    function swap(address _tokenIn, uint256 _amountIn) public nonReentrant returns (uint256 amountOut) {
        require(_tokenIn == address(token1) || _tokenIn == address(token2), "Invalid token");
        require(_amountIn > 0, "Amount must be greater than 0");

        IERC20 tokenIn = IERC20(_tokenIn);
        IERC20 tokenOut = _tokenIn == address(token1) ? token2 : token1;

        amountOut = calculateSwapOutput(_tokenIn, _amountIn);

        require(amountOut > 0 && amountOut <= tokenOut.balanceOf(address(this)), "Insufficient liquidity");

        tokenIn.safeTransferFrom(msg.sender, address(this), _amountIn);
        tokenOut.safeTransfer(msg.sender, amountOut);

        // 记录交易
        trades.push(Trade({
            user: msg.sender,
            operation: "Swap",
            tokenIn: _tokenIn,
            amountIn: _amountIn,
            tokenOut: address(tokenOut),
            amountOut: amountOut,
            timestamp: block.timestamp
        }));

        if (_tokenIn == address(token1)) {
            token1Balance += _amountIn;
            token2Balance -= amountOut;
        } else {
            token2Balance += _amountIn;
            token1Balance -= amountOut;
        }

        emit Swap(msg.sender, _tokenIn, _amountIn, address(tokenOut), amountOut);
    }

    function getTradeHistory() public view returns (Trade[] memory) {
        return trades;
    }

    function swapWithSlippage(address _tokenIn, uint256 _amountIn, uint256 _minAmountOut) external nonReentrant returns (uint256 amountOut) {
        amountOut = swap(_tokenIn, _amountIn);
        require(amountOut >= _minAmountOut, "Slippage tolerance exceeded");
        return amountOut;
    }

    function calculateSwapOutput(address _tokenIn, uint256 _amountIn) internal view returns (uint256) {
        uint256 reserveIn = _tokenIn == address(token1) ? token1Balance : token2Balance;
        uint256 reserveOut = _tokenIn == address(token1) ? token2Balance : token1Balance;
        
        uint256 amountInWithFee = _amountIn * 997; // 0.3% fee
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        return numerator / denominator;
    }

    function getReserves() public view returns (uint256 reserve1, uint256 reserve2) {
        return (token1Balance, token2Balance);
    }

    function getPrice(address _tokenIn, uint256 _amountIn) public view returns (uint256) {
        return calculateSwapOutput(_tokenIn, _amountIn);
    }
}
