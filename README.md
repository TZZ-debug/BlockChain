# Decentralized Exchange (DEX) and Token Market Contract Suite

This project contains a set of Solidity smart contracts for a decentralized exchange (DEX) and a token market, including a basic ERC20 token implementation. The contracts are designed to work together to allow users to trade tokens and interact with a marketplace for token sales.

## Contracts Overview

1. **Token.sol**
   - An ERC20 compatible token contract that allows for the minting of an initial supply to the deployer.

2. **DEX.sol**
   - A decentralized exchange contract that facilitates the swapping of tokens.
   - Allows users to add liquidity and earn fees from trades.
   - Provides functions for swapping tokens with a 0.3% fee.

3. **TokenMarket.sol**
   - A marketplace contract for buying and selling tokens at a set price.
   - Allows the owner to list and delist tokens.
   - Collects a market fee on transactions.

4. **User.sol**
   - A contract representing a user in the system.
   - Interacts with the TokenMarket and DEX to perform trades.
   - Allows users to buy tokens from the market, sell tokens, and swap tokens on the DEX.
