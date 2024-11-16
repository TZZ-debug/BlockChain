// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenMarket is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct TokenInfo {
        uint256 price;      // Price (in wei)
        bool isListed;      // Whether the token is listed
        uint256 available;  // Available amount on platform
    }

    mapping(address => TokenInfo) public listedTokens;
    mapping(address => mapping(address => uint256)) public userTokenBalances;

    uint256 public marketFeeRate = 25;  // Default fee rate 0.25% = marketFeeRate / FEE_DENOMINATOR
    uint256 public constant FEE_DENOMINATOR = 10000;  // Fee precision is 1/10000
    address public feeCollector;  // Fee collector address
    uint256 private constant FEE_PRECISION = 1e18;  // Fee calculation precision (to prevent decimal truncation)
    uint256 public accumulatedFees;  // Accumulated fees

    event TokenListed(address indexed token, uint256 price, uint256 amount);
    event TokenDelisted(address indexed token);
    event TokenPurchased(address indexed buyer, address indexed token, uint256 amount, uint256 cost, uint256 fee);
    event TokenSold(address indexed seller, address indexed token, uint256 amount, uint256 earning);
    event FeeRateUpdated(uint256 oldRate, uint256 newRate);
    event FeesCollected(uint256 amount);

    constructor() Ownable(msg.sender) {
        feeCollector = msg.sender;
    }

    // Set market fee rate
    function setMarketFeeRate(uint256 _newRate) external onlyOwner {
        require(_newRate <= 500, "Fee rate cannot exceed 5%"); // Maximum 5%
        uint256 oldRate = marketFeeRate;
        marketFeeRate = _newRate;
        emit FeeRateUpdated(oldRate, _newRate);
    }

    // Collect accumulated fees
    function collectFees() external {
        require(msg.sender == feeCollector, "Only fee collector can collect fees");
        uint256 feesToCollect = accumulatedFees / FEE_PRECISION;
        
        accumulatedFees = accumulatedFees % FEE_PRECISION;
        
        (bool success, ) = feeCollector.call{value: feesToCollect}("");
        require(success, "Fee transfer failed");
        
        emit FeesCollected(feesToCollect);
    }

    // Set fee collector address
    function setFeeCollector(address _newCollector) external onlyOwner {
        require(_newCollector != address(0), "Invalid address");
        feeCollector = _newCollector;
    }

    // List new token
    function listToken(address _token, uint256 _priceInWei, uint256 _amount) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        require(_priceInWei > 0, "Price must be greater than 0");
        require(_amount > 0, "Amount must be greater than 0");

        IERC20 token = IERC20(_token);
        
        // Check allowance and balance
        uint256 allowance = token.allowance(msg.sender, address(this));
        require(allowance >= _amount, "Insufficient allowance");
        
        uint256 balance = token.balanceOf(msg.sender);
        require(balance >= _amount, "Insufficient balance");

        // Transfer using SafeERC20
        token.safeTransferFrom(msg.sender, address(this), _amount);

        listedTokens[_token] = TokenInfo({
            price: _priceInWei,
            isListed: true,
            available: _amount
        });

        emit TokenListed(_token, _priceInWei, _amount);
    }
 
    // Delist token
    function delistToken(address _token) external onlyOwner {
        TokenInfo storage tokenInfo = listedTokens[ _token];
        require(tokenInfo.isListed, "Token not listed");
        
        IERC20 token = IERC20(_token);
        uint256 contractBalance = token.balanceOf(address(this));
        
        // Ensure contract has sufficient token balance
        require(contractBalance >= tokenInfo.available, "Contract balance too low");
        
        // Return remaining tokens to contract owner using SafeERC20
        if (tokenInfo.available > 0) {
            token.safeTransfer(owner(), tokenInfo.available);
        }
        
        delete listedTokens[_token];  // Completely remove token info
        
        emit TokenDelisted(_token);
    }

    // Buy token function
    function buyToken(address _token, uint256 _amount) external payable {
        TokenInfo storage tokenInfo = listedTokens[_token];
        require(tokenInfo.isListed, "Token not listed");
        require(tokenInfo.available >= _amount, "Insufficient token balance");

        uint256 totalCost = (_amount * tokenInfo.price) / 1e18;
        uint256 fee = (totalCost * marketFeeRate * FEE_PRECISION) / FEE_DENOMINATOR;
        uint256 totalPayment = totalCost + fee;
        
        require(msg.value >= totalPayment, "Insufficient ETH sent");

        // Update state
        tokenInfo.available -= _amount;
        userTokenBalances[msg.sender][_token] += _amount;
        accumulatedFees += fee;

        // Transfer tokens
        IERC20(_token).safeTransfer(msg.sender, _amount);

        // Handle refund
        if (msg.value > totalPayment) {
            (bool success, ) = msg.sender.call{value: msg.value - totalPayment}("");
            require(success, "ETH refund failed");
        }

        emit TokenPurchased(msg.sender, _token, _amount, totalCost, fee);
    }

    // Sell token
    function sellToken(address _token, uint256 _amount) external {
        TokenInfo storage tokenInfo = listedTokens[_token];
        require(tokenInfo.isListed, "Token not listed");
        require(_amount > 0, "Amount must be greater than 0");

        IERC20 token = IERC20(_token);
        
        // Check allowance and balance
        uint256 allowance = token.allowance(msg.sender, address(this));
        require(allowance >= _amount, "Insufficient allowance");
        
        uint256 balance = token.balanceOf(msg.sender);
        require(balance >= _amount, "Insufficient balance");

        // Calculate selling price and fee
        uint256 totalEarning = (_amount * tokenInfo.price) / 1e18;
        uint256 fee = (totalEarning * marketFeeRate * FEE_PRECISION) / FEE_DENOMINATOR;
        uint256 actualEarning = totalEarning - (fee / FEE_PRECISION);
        
        require(address(this).balance >= actualEarning, "Insufficient contract balance");
        
        // Transfer tokens to contract
        token.safeTransferFrom(msg.sender, address(this), _amount);
        
        // Update state
        userTokenBalances[msg.sender][_token] -= _amount;
        tokenInfo.available += _amount;
        accumulatedFees += fee;  // Accumulate fees
        
        // Transfer ETH to seller
        (bool success, ) = msg.sender.call{value: actualEarning}("");
        require(success, "ETH transfer failed");
        
        emit TokenSold(msg.sender, _token, _amount, actualEarning);
    }

    // Modified get token info function
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

    // Real-time balance update function to monitor the amount change in the User contract
    function updateUserBalance(address user, address _token) public {
        IERC20 tokenContract = IERC20(_token);
        userTokenBalances[user][_token] = tokenContract.balanceOf(user);
    }

    // Fallback function to receive ETH
    receive() external payable {}
}
