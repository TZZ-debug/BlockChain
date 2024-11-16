// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interface for TokenMarket contract functions
interface ITokenMarket {
    function buyToken(address _token, uint256 _amount) external payable;
    function sellToken(address _token, uint256 _amount) external;
    function updateUserBalance(address user, address _token) external;
    function getTokenInfo(address _token) external view returns (
        uint256 price,
        bool isListed,
        uint256 available,
        uint256 userBalance,
        uint256 currentFeeRate
    );
}