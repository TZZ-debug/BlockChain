// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenMarket is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct TokenInfo {
        uint256 price;      // 价格（以wei为单位）
        bool isListed;      // 是否已上市
        uint256 available;  // 平台可用数量
    }

    mapping(address => TokenInfo) public listedTokens;
    mapping(address => mapping(address => uint256)) public userTokenBalances;

    uint256 public marketFeeRate = 25; // 默认0.25%的手续费 = marketFeeRate / FEE_DENOMINATOR
    uint256 public constant FEE_DENOMINATOR = 10000; // 费率精度为万分之一
    address public feeCollector; // 手续费收集地址
    uint256 private constant FEE_PRECISION = 1e18;  // 计算手续费的精度(确保小数点后的数不被抹除)
    uint256 public accumulatedFees; // 累积的手续费

    event TokenListed(address indexed token, uint256 price, uint256 amount);
    event TokenDelisted(address indexed token);
    event TokenPurchased(address indexed buyer, address indexed token, uint256 amount, uint256 cost, uint256 fee);
    event TokenSold(address indexed seller, address indexed token, uint256 amount, uint256 earning);
    event FeeRateUpdated(uint256 oldRate, uint256 newRate);
    event FeesCollected(uint256 amount);

    constructor() Ownable(msg.sender) {
        feeCollector = msg.sender;
    }

    // 设置市场手续费率
    function setMarketFeeRate(uint256 _newRate) external onlyOwner {
        require(_newRate <= 500, "Fee rate cannot exceed 5%"); // 最高5%
        uint256 oldRate = marketFeeRate;
        marketFeeRate = _newRate;
        emit FeeRateUpdated(oldRate, _newRate);
    }

    // 收集累积的手续费
    function collectFees() external {
        require(msg.sender == feeCollector, "Only fee collector can collect fees");
        uint256 feesToCollect = accumulatedFees / FEE_PRECISION;
        
        accumulatedFees = accumulatedFees % FEE_PRECISION;
        
        (bool success, ) = feeCollector.call{value: feesToCollect}("");
        require(success, "Fee transfer failed");
        
        emit FeesCollected(feesToCollect);
    }

    // 设置手续费收集地址
    function setFeeCollector(address _newCollector) external onlyOwner {
        require(_newCollector != address(0), "Invalid address");
        feeCollector = _newCollector;
    }

    // 上市新代币
    function listToken(address _token, uint256 _priceInWei, uint256 _amount) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        require(_priceInWei > 0, "Price must be greater than 0");
        require(_amount > 0, "Amount must be greater than 0");

        IERC20 token = IERC20(_token);
        
        // 检查授权和余额
        uint256 allowance = token.allowance(msg.sender, address(this));
        require(allowance >= _amount, "Insufficient allowance");
        
        uint256 balance = token.balanceOf(msg.sender);
        require(balance >= _amount, "Insufficient balance");

        // 使用 SafeERC20 进行转账
        token.safeTransferFrom(msg.sender, address(this), _amount);

        listedTokens[_token] = TokenInfo({
            price: _priceInWei,
            isListed: true,
            available: _amount
        });

        emit TokenListed(_token, _priceInWei, _amount);
    }
 
    // 下架代币
    function delistToken(address _token) external onlyOwner {
        TokenInfo storage tokenInfo = listedTokens[_token];
        require(tokenInfo.isListed, "Token not listed");
        
        IERC20 token = IERC20(_token);
        uint256 contractBalance = token.balanceOf(address(this));
        
        // 确保合约有足够的代币余额
        require(contractBalance >= tokenInfo.available, "Contract balance too low");
        
        // 使用 SafeERC20 将剩余代币返还给合约拥有者
        if (tokenInfo.available > 0) {
            token.safeTransfer(owner(), tokenInfo.available);
        }
        
        delete listedTokens[_token];  // 完全删除代币信息
        
        emit TokenDelisted(_token);
    }

    // 购买代币函数
    function buyToken(address _token, uint256 _amount) external payable {
        TokenInfo storage tokenInfo = listedTokens[_token];
        require(tokenInfo.isListed, "Token not listed");
        require(tokenInfo.available >= _amount, "Insufficient token balance");

        uint256 totalCost = (_amount * tokenInfo.price) / 1e18;
        uint256 fee = (totalCost * marketFeeRate * FEE_PRECISION) / FEE_DENOMINATOR;
        uint256 totalPayment = totalCost + fee;
        
        require(msg.value >= totalPayment, "Insufficient ETH sent");

        // 更新状态
        tokenInfo.available -= _amount;
        userTokenBalances[msg.sender][_token] += _amount;
        accumulatedFees += fee;

        // 转移代币
        IERC20(_token).safeTransfer(msg.sender, _amount);

        // 处理找零
        if (msg.value > totalPayment) {
            (bool success, ) = msg.sender.call{value: msg.value - totalPayment}("");
            require(success, "ETH refund failed");
        }

        emit TokenPurchased(msg.sender, _token, _amount, totalCost, fee);
    }

    // 卖出代币
    function sellToken(address _token, uint256 _amount) external {
        TokenInfo storage tokenInfo = listedTokens[_token];
        require(tokenInfo.isListed, "Token not listed");
        require(_amount > 0, "Amount must be greater than 0");

        IERC20 token = IERC20(_token);
        
        // 检查授权和余额
        uint256 allowance = token.allowance(msg.sender, address(this));
        require(allowance >= _amount, "Insufficient allowance");
        
        uint256 balance = token.balanceOf(msg.sender);
        require(balance >= _amount, "Insufficient balance");

        // 计算卖出价格和手续费
        uint256 totalEarning = (_amount * tokenInfo.price) / 1e18;
        uint256 fee = (totalEarning * marketFeeRate * FEE_PRECISION) / FEE_DENOMINATOR;
        uint256 actualEarning = totalEarning - (fee / FEE_PRECISION);
        
        require(address(this).balance >= actualEarning, "Insufficient contract balance");
        
        // 转移代币到合约
        token.safeTransferFrom(msg.sender, address(this), _amount);
        
        // 更新状态
        userTokenBalances[msg.sender][_token] -= _amount;
        tokenInfo.available += _amount;
        accumulatedFees += fee;  // 累积手续费
        
        // 转移ETH给卖家
        (bool success, ) = msg.sender.call{value: actualEarning}("");
        require(success, "ETH transfer failed");
        
        emit TokenSold(msg.sender, _token, _amount, actualEarning);
    }

    // 修改后的查看代币信息函数
    function getTokenInfo(address _token) external view returns (
        uint256 price,
        bool isListed,
        uint256 available,
        uint256 userBalance,
        uint256 currentFeeRate
    ) {
        TokenInfo storage tokenInfo = listedTokens[_token];
        return (
            tokenInfo.price,
            tokenInfo.isListed,
            tokenInfo.available,
            userTokenBalances[msg.sender][_token],
            marketFeeRate
        );
    }

    // 实时余额更新函数，用于监控 User 合约中的金额变化
    function updateUserBalance(address user, address _token) public {
        IERC20 tokenContract = IERC20(_token);
        userTokenBalances[user][_token] = tokenContract.balanceOf(user);
    }

    // 接收ETH的回退函数
    receive() external payable {}
}