// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// 导入 OpenZeppelin 的 ERC20 实现
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20(name, symbol) {
        // 初始供应量以最小单位（通常是 10^18）铸造给合约部署者
        _mint(msg.sender, initialSupply * (10 ** uint256(decimals())));
    }
}