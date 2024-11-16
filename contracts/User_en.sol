// User.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ITokenMarket.sol";
import "./IDEX.sol";

contract User is Ownable {
    using SafeERC20 for IERC20;

    ITokenMarket public tokenMarket;
    IDEX public dex;

    event TokenBought(address token, uint256 amount, uint256 cost);
    event TokenSold(address token, uint256 amount, uint256 received);
    event TokenSwapped(address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);

    constructor(address _tokenMarket, address _dex) Ownable(msg.sender) {
        require(_tokenMarket != address(0) && _dex != address(0), "Invalid addresses");
        tokenMarket = ITokenMarket(_tokenMarket);
        dex = IDEX(_dex);
    }

    // TokenMarket related functions
    function buyTokenFromMarket(address _token, uint256 _amount) external payable {
        tokenMarket.buyToken{value: msg.value}(_token, _amount);
        emit TokenBought(_token, _amount, msg.value);
    }

    function sellTokenToMarket(address _token, uint256 _amount) external {
        // First approve TokenMarket contract to use tokens
        IERC20 token = IERC20(_token);
        token.approve(address(tokenMarket), _amount);
        tokenMarket.sellToken(_token, _amount);
        
        // Reset approval
        token.approve(address(tokenMarket), 0);
        
        emit TokenSold(_token, _amount, 0); // The received amount needs to be obtained from events
    }

    // TokenMarket contract real-time update function
    function updateMarketBalance(address token) public {
        tokenMarket.updateUserBalance(address(this), token);
    }

    function getMarketTokenInfo(address _token) external view returns (
        uint256 price,
        bool isListed,
        uint256 available,
        uint256 userBalance,
        uint256 currentFeeRate
    ) {
        return tokenMarket.getTokenInfo(_token);
    }

    // DEX related functions
    function swapTokens(address _tokenIn, uint256 _amountIn) external returns (uint256) {
        // First approve DEX contract to use tokens
        IERC20 token = IERC20(_tokenIn);
        token.approve(address(dex), _amountIn);
        
        uint256 amountOut = dex.swap(_tokenIn, _amountIn);
        
        updateMarketBalance(_tokenIn);

        // Reset approval
        token.approve(address(dex), 0);
        
        emit TokenSwapped(_tokenIn, _amountIn, address(0), amountOut);
        return amountOut;
    }

    function checkTokenBalance(address _token) external view returns (uint256) {
        return dex.getUserTokenBalance(_token);
    }

    function getTokenPrice(address _tokenIn, uint256 _amountIn) external view returns (uint256) {
        return dex.getPrice(_tokenIn, _amountIn);
    }

    function getDEXReserves() external view returns (uint256 reserve1, uint256 reserve2) {
        return dex.getReserves();
    }

    // Approval function: User contract authorizes external contracts to operate tokens owned by User
    function approveToken(address _token, address _spender, uint256 _amount) external onlyOwner {
        IERC20 token = IERC20(_token);
        token.approve(_spender, _amount);
    }

    // Withdraw ETH from the contract
    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        (bool success, ) = owner().call{value: balance}("");
        require(success, "ETH transfer failed");
    }

    // Withdraw tokens from the contract
    function withdrawToken(address _token) external onlyOwner {
        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        token.transfer(owner(), balance);
    }

    // Fallback function to receive ETH
    receive() external payable {}
}



