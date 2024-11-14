// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenMarket is Ownable {
    using SafeERC20 for IERC20;

    struct TokenInfo {
        uint256 price;      // 价格（以wei为单位）
        bool isListed;      // 是否已上市
        uint256 available;  // 平台可用数量
    }

    mapping(address => TokenInfo) public listedTokens;
    mapping(address => mapping(address => uint256)) public userTokenBalances; // 恢复这个映射

    event TokenListed(address indexed token, uint256 price, uint256 amount);
    event TokenDelisted(address indexed token);
    event TokenPurchased(address indexed buyer, address indexed token, uint256 amount, uint256 cost);
    event TokenSold(address indexed seller, address indexed token, uint256 amount, uint256 earning);

    constructor() Ownable(msg.sender) {}

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

    // 购买代币
    function buyToken(address _token, uint256 _amount) external payable {
        TokenInfo storage tokenInfo = listedTokens[_token];
        require(tokenInfo.isListed, "Token not listed");
        require(tokenInfo.available >= _amount, "Insufficient token balance");

        uint256 totalCost = (_amount * tokenInfo.price) / 1e18;
        require(msg.value >= totalCost, "Insufficient ETH sent");

       // 更新市场Token剩余和用户Token余额状态
        tokenInfo.available -= _amount;
        userTokenBalances[msg.sender][_token] += _amount; // 记录用户购买的代币

        // 直接将代币转给买家
        IERC20(_token).safeTransfer(msg.sender, _amount);

        // 退还多余的ETH
        if (msg.value > totalCost) {
            (bool success, ) = msg.sender.call{value: msg.value - totalCost}("");
            require(success, "ETH refund failed");
        }

        emit TokenPurchased(msg.sender, _token, _amount, totalCost);
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

        // 计算卖出价格
        uint256 totalEarning = (_amount * tokenInfo.price) / 1e18;
        require(address(this).balance >= totalEarning, "Insufficient contract balance");

        // 转移代币到合约
        token.safeTransferFrom(msg.sender, address(this), _amount);

        // 更新用户Token余额和市场Token剩余状态
        userTokenBalances[msg.sender][_token] -= _amount;
        tokenInfo.available += _amount;

        // 转移Token给卖家
        (bool success, ) = msg.sender.call{value: totalEarning}("");
        require(success, "ETH transfer failed");

        emit TokenSold(msg.sender, _token, _amount, totalEarning);
    }

    // 查看代币信息
    function getTokenInfo(address _token) external view returns (
        uint256 price,
        bool isListed,
        uint256 available,
        uint256 userBalance
    ) {
        TokenInfo storage tokenInfo = listedTokens[_token];
        return (
            tokenInfo.price,  // 查询Token价格
            tokenInfo.isListed,  // 查询Token是否在售
            tokenInfo.available,  // 查询市场上可购买的Token数
            userTokenBalances[msg.sender][_token]  // 查询用户钱包中的Token余额
        );
    }
}
