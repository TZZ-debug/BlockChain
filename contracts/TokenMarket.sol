// TokenMarket.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenMarket is Ownable {
    struct TokenInfo {
        uint256 price;      // 价格（以wei为单位）
        bool isListed;      // 是否已上市
        uint256 available;  // 平台可用数量
    }

    mapping(address => TokenInfo) public listedTokens;
    // 用户在平台上的代币余额
    mapping(address => mapping(address => uint256)) public userTokenBalances;

    event TokenListed(address indexed token, uint256 price, uint256 amount);
    event TokenDelisted(address indexed token);
    event TokenPurchased(address indexed buyer, address indexed token, uint256 amount, uint256 cost);
    event TokenSold(address indexed seller, address indexed token, uint256 amount, uint256 earning);

    constructor() Ownable(msg.sender) {}

    // 上市新代币
    function listToken(address _token, uint256 _price, uint256 _amount) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        require(_price > 0, "Price must be greater than 0");
        require(_amount > 0, "Amount must be greater than 0");

        IERC20 token = IERC20(_token);
        require(token.transferFrom(msg.sender, address(this), _amount), "Transfer failed");

        listedTokens[_token] = TokenInfo({
            price: _price,
            isListed: true,
            available: _amount
        });

        emit TokenListed(_token, _price, _amount);
    }

    // 下架代币
    function delistToken(address _token) external onlyOwner {
        TokenInfo storage tokenInfo = listedTokens[_token];
        require(tokenInfo.isListed, "Token not listed");
        
        // 将剩余代币返还给合约拥有者
        if (tokenInfo.available > 0) {
            IERC20(_token).transfer(owner(), tokenInfo.available);
        }
        
        tokenInfo.isListed = false;
        tokenInfo.available = 0;
        
        emit TokenDelisted(_token);
    }

    // 购买代币
    function buyToken(address _token, uint256 _amount) external payable {
        TokenInfo storage tokenInfo = listedTokens[_token];
        require(tokenInfo.isListed, "Token not listed");
        require(tokenInfo.available >= _amount, "Insufficient token balance");

        uint256 cost = tokenInfo.price * _amount;
        require(msg.value >= cost, "Insufficient payment");

        tokenInfo.available -= _amount;
        userTokenBalances[msg.sender][_token] += _amount;

        // 退还多余的ETH
        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }

        emit TokenPurchased(msg.sender, _token, _amount, cost);
    }

    // 卖出代币
    function sellToken(address _token, uint256 _amount) external {
        TokenInfo storage tokenInfo = listedTokens[_token];
        require(tokenInfo.isListed, "Token not listed");
        require(userTokenBalances[msg.sender][_token] >= _amount, "Insufficient balance");

        uint256 earning = tokenInfo.price * _amount;
        require(address(this).balance >= earning, "Insufficient contract balance");

        userTokenBalances[msg.sender][_token] -= _amount;
        tokenInfo.available += _amount;

        payable(msg.sender).transfer(earning);

        emit TokenSold(msg.sender, _token, _amount, earning);
    }

    // 提取代币（从平台余额中提取到钱包）
    function withdrawToken(address _token, uint256 _amount) external {
        require(userTokenBalances[msg.sender][_token] >= _amount, "Insufficient balance");
        
        userTokenBalances[msg.sender][_token] -= _amount;
        IERC20(_token).transfer(msg.sender, _amount);
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
            tokenInfo.price,
            tokenInfo.isListed,
            tokenInfo.available,
            userTokenBalances[msg.sender][_token]
        );
    }

    // 获取用户在平台上的代币余额
    function getUserBalance(address _user, address _token) external view returns (uint256) {
        return userTokenBalances[_user][_token];
    }
}
