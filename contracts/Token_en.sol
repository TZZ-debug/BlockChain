// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import OpenZeppelin's ERC20 implementation
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20(name, symbol) {
        // Mint initial supply in smallest unit (usually 10^18) to contract deployer
        _mint(msg.sender, initialSupply * (10 ** uint256(decimals())));
    }
}
