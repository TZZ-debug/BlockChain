// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Define IDEX interface
interface IDEX {
    function addLiquidity(uint256 token1Amount, uint256 token2Amount) external;
    function removeLiquidity(uint256 token1Amount, uint256 token2Amount) external;
    function swap(address tokenIn, uint256 amountIn) external returns (uint256);
    function getReserves() external view returns (uint256, uint256);
    function swapWithSlippage(address _tokenIn, uint256 _amountIn, uint256 _minAmountOut) external returns (uint256 amountOut);
}

// Reentrancy Attack Contract
contract ReentrancyAttacker {
    IDEX public dex;
    IERC20 public token1;
    IERC20 public token2;
    uint256 public attackAmount;

    event AttackResult(string message, uint256 value);

    constructor(address _dex, address _token1, address _token2) {
        dex = IDEX(_dex);
        token1 = IERC20(_token1);
        token2 = IERC20(_token2);
    }

    function attack(uint256 _amount) external {
        attackAmount = _amount;
        token1.approve(address(dex), _amount);
        dex.swap(address(token1), _amount);
    }

    function onERC20Received(address, uint256 _amount) external returns (bytes4) {
        if (attackAmount > 0) {
            try dex.swap(address(token2), _amount) {
                emit AttackResult("Reentrancy attack succeeded", _amount);
            } catch {
                emit AttackResult("Reentrancy attack failed", 0);
            }
            attackAmount = 0;
        }
        return this.onERC20Received.selector;
    }

    function getBalance(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }
}

// Main Test Contract
contract DEXTestSuite {
    IERC20 public token1;
    IERC20 public token2;
    IDEX public dex;
    ReentrancyAttacker public attacker;
    
    event TestResult(string message, uint256 value);
    event TestInfo(string message);

    constructor(address _token1, address _token2, address _dex) {
        // Use deployed contract addresses
        token1 = IERC20(_token1);
        token2 = IERC20(_token2);
        dex = IDEX(_dex);

        // Deploy attacker contract
        attacker = new ReentrancyAttacker(
            _dex,
            _token1,
            _token2
        );

        // Initialize approvals
        token1.approve(address(dex), type(uint256).max);
        token2.approve(address(dex), type(uint256).max);
    }

    // Add initialization function
    function initialize() public view {
        // Check balances and approvals
        require(
            token1.balanceOf(address(this)) > 0,
            "Insufficient token1 balance"
        );
        require(
            token2.balanceOf(address(this)) > 0,
            "Insufficient token2 balance"
        );
    }

    // Test adding liquidity
    function testAddLiquidity() public {
        uint256 amount1 = 1000 * 10**18; 
        uint256 amount2 = 1000 * 10**18; 
        
        uint256 balanceBefore1 = token1.balanceOf(address(this));
        uint256 balanceBefore2 = token2.balanceOf(address(this));
        
        token1.approve(address(dex), amount1);
        token2.approve(address(dex), amount2);
        
        dex.addLiquidity(amount1, amount2);
        
        uint256 balanceAfter1 = token1.balanceOf(address(this));
        uint256 balanceAfter2 = token2.balanceOf(address(this));
        
        require(balanceBefore1 - balanceAfter1 == amount1, "Incorrect token1 transfer");
        require(balanceBefore2 - balanceAfter2 == amount2, "Incorrect token2 transfer");
        
        emit TestResult("Add liquidity test passed", amount1);
    }

    // Test token swap
    function testSwap() public {
        uint256 swapAmount = 50 * 10**18; 
        
        uint256 balanceBefore = token1.balanceOf(address(this));
        token1.approve(address(dex), swapAmount);
        
        uint256 amountOut = dex.swap(address(token1), swapAmount);
        
        uint256 balanceAfter = token1.balanceOf(address(this));
        require(balanceBefore - balanceAfter == swapAmount, "Incorrect swap amount");
        
        emit TestResult("Swap test passed", amountOut);
    }

    // Test price manipulation
    function testPriceManipulation() public {
        uint256 manipulationAmount = 2000 * 10**18;
        
        (uint256 reserve1Before, uint256 reserve2Before) = dex.getReserves();
        
        token1.approve(address(dex), manipulationAmount);
        dex.swap(address(token1), manipulationAmount);
        
        (uint256 reserve1After, uint256 reserve2After) = dex.getReserves();
        
        require(reserve1After > reserve1Before, "Reserve1 manipulation failed");
        require(reserve2After < reserve2Before, "Reserve2 manipulation failed");
        
        emit TestResult("Price manipulation test passed", 
            (reserve1After - reserve1Before) + (reserve2Before - reserve2After)
        );
    }

    // Test reentrancy attack
    function testReentrancy() public {
        // Reduce reentrancy attack amount
        uint256 attackAmount = 50 * 10**18; // Reduced from 100 to 50
        
        token1.transfer(address(attacker), attackAmount);
        attacker.attack(attackAmount);
        
        emit TestResult("Reentrancy test completed", attackAmount);
    }

    // Function to check balances
    function getBalances() public view returns (uint256 balance1, uint256 balance2) {
        balance1 = token1.balanceOf(address(this));
        balance2 = token2.balanceOf(address(this));
    }

    // Run all tests
    function runAllTests() public {
        // Check initial state first
        initialize();
        // Run tests
        testAddLiquidity();
        testSwap();
        testPriceManipulation();
        testReentrancy();
    }

    // Check contract state
    function checkState() public view returns (
        uint256 token1Balance,
        uint256 token2Balance,
        uint256 token1Allowance,
        uint256 token2Allowance
    ) {
        return (
            token1.balanceOf(address(this)),
            token2.balanceOf(address(this)),
            token1.allowance(address(this), address(dex)),
            token2.allowance(address(this), address(dex))
        );
    }
}
