// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interface for DEX contract functions
interface IDEX {
    function swap(address _tokenIn, uint256 _amountIn) external returns (uint256 amountOut);
    function getUserTokenBalance(address tokenAddress) external view returns (uint256);
    function getPrice(address _tokenIn, uint256 _amountIn) external view returns (uint256);
    function getReserves() external view returns (uint256 reserve1, uint256 reserve2);
}
