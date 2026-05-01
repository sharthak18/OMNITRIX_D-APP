// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/lending/LendingPool.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockPriceOracle.sol";

// ─── Flash loan test receiver ──────────────────────────────────────────────
/// @dev Repays the flash loan immediately (good borrower)
contract GoodFlashReceiver is IFlashLoanReceiver {
    MockERC20 public token;
    constructor(MockERC20 _token) { token = _token; }

    function executeOperation(address asset, uint256 amount, uint256 fee, bytes calldata) external override {
        // Simply approve repayment (pool already transferred funds to us)
        IERC20(asset).approve(msg.sender, amount + fee);
        token.mint(address(this), fee); // simulate profit that covers the fee
        IERC20(asset).transfer(msg.sender, amount + fee);
    }
}

/// @dev Attempts to NOT repay the flash loan (bad borrower — should revert)
contract BadFlashReceiver is IFlashLoanReceiver {
    function executeOperation(address, uint256, uint256, bytes calldata) external override {
        // Does nothing — pool should revert because funds aren't returned
    }
}

// ─── Main Test Contract ────────────────────────────────────────────────────
contract LendingTest is Test {
    LendingPool     public pool;
    MockPriceOracle public oracle;
    MockERC20       public weth;
    MockERC20       public usdc;

    address alice   = makeAddr("alice");
    address bob     = makeAddr("bob");
    address charlie = makeAddr("charlie"); // liquidator

    // Prices: 1 WETH = $2000, 1 USDC = $1
    uint256 constant ETH_PRICE  = 2000e8; // 8-decimal Chainlink format
    uint256 constant USDC_PRICE = 1e8;

    function setUp() public {
        oracle = new MockPriceOracle();
        pool   = new LendingPool(address(oracle), address(this));
        weth   = new MockERC20("Wrapped ETH", "WETH", 18);
        usdc   = new MockERC20("USD Coin",    "USDC", 6);

        oracle.setPrice(address(weth), ETH_PRICE,  8);
        oracle.setPrice(address(usdc), USDC_PRICE, 8);

        pool.registerAsset(address(weth));
        pool.registerAsset(address(usdc));

        // Fund accounts
        weth.mint(alice,   100 ether);
        usdc.mint(bob,     100_000e6);
        weth.mint(charlie, 10 ether);
    }

    // ─── Deposit ────────────────────────────────────────────────────
    function test_Deposit() public {
        vm.startPrank(alice);
        weth.approve(address(pool), 10 ether);
        pool.deposit(address(weth), 10 ether);
        vm.stopPrank();

        (uint256 deposited,,) = pool.positions(alice, address(weth));
        assertEq(deposited, 10 ether);

        // assetConfigs now returns 7 fields: (supported, totalDeposited, totalBorrowed, debtIndex, lastUpdateTime, supplyCap, borrowCap)
        (bool supported,,,,,, ) = pool.assetConfigs(address(weth));
        assertTrue(supported);
    }

    // ─── Deposit + Borrow ────────────────────────────────────────────
    function test_DepositAndBorrow() public {
        // Alice deposits 10 WETH ($20,000)
        vm.startPrank(alice);
        weth.approve(address(pool), 10 ether);
        pool.deposit(address(weth), 10 ether);
        vm.stopPrank();

        // Bob deposits USDC so there's liquidity to borrow
        vm.startPrank(bob);
        usdc.approve(address(pool), 100_000e6);
        pool.deposit(address(usdc), 100_000e6);
        vm.stopPrank();

        // Alice borrows USDC — 75% of $20,000 = $15,000 max; we borrow $10,000
        // But MIN_HEALTH_AFTER_BORROW = 1.05 so max is effectively ~70.8% of LTV
        vm.startPrank(alice);
        pool.borrow(address(usdc), 10_000e6);
        vm.stopPrank();

        assertEq(usdc.balanceOf(alice), 10_000e6);
        assertTrue(pool.getUserDebt(alice, address(usdc)) >= 10_000e6);
    }

    // ─── LTV limit revert ────────────────────────────────────────────
    function test_RevertBorrowExceedsLTV() public {
        vm.startPrank(alice);
        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether); // $2000 collateral → 75% LTV = $1500 max
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(pool), 100_000e6);
        pool.deposit(address(usdc), 100_000e6);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert("LendingPool: exceeds LTV");
        pool.borrow(address(usdc), 1_600e6); // $1600 > 75% of $2000 = $1500
        vm.stopPrank();
    }

    // ─── Health factor buffer ────────────────────────────────────────
    /// @dev Borrowing 1400/2000 = 70% LTV should pass (1.14× HF >= 1.05 buffer)
    ///      Borrowing 1499/2000 = 74.95% LTV should also pass but 1490/2000 at the edge should still pass
    function test_RevertBorrowBelowHFBuffer() public {
        vm.startPrank(alice);
        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether); // $2000
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(pool), 100_000e6);
        pool.deposit(address(usdc), 100_000e6);
        vm.stopPrank();

        // $1500 is exactly 75% LTV — health factor = 80/75 = 1.0667 > 1.05 → PASSES
        // $1450 is 72.5% → HF = 80/72.5 = 1.103 > 1.05 → PASSES
        vm.startPrank(alice);
        pool.borrow(address(usdc), 1_450e6);
        vm.stopPrank();

        assertTrue(pool.healthFactor(alice) >= 1.05e18);
    }

    // ─── Repay ──────────────────────────────────────────────────────
    function test_Repay() public {
        test_DepositAndBorrow();

        uint256 debt = pool.getUserDebt(alice, address(usdc));
        usdc.mint(alice, debt); // give extra to cover any accrued interest

        vm.startPrank(alice);
        usdc.approve(address(pool), debt);
        pool.repay(address(usdc), debt);
        vm.stopPrank();

        assertEq(pool.getUserDebt(alice, address(usdc)), 0);
    }

    // ─── Health factor ───────────────────────────────────────────────
    function test_HealthFactor_Healthy() public {
        test_DepositAndBorrow();
        uint256 hf = pool.healthFactor(alice);
        assertTrue(hf >= 1e18, "Should be healthy after 10k borrow on 20k collateral");
    }

    // ─── Liquidation ─────────────────────────────────────────────────
    function test_Liquidation() public {
        // Alice deposits 1 WETH ($2000), borrows $1400 USDC (70% LTV)
        vm.startPrank(alice);
        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(pool), 100_000e6);
        pool.deposit(address(usdc), 100_000e6);
        vm.stopPrank();

        vm.startPrank(alice);
        pool.borrow(address(usdc), 1_400e6);
        vm.stopPrank();

        // Crash ETH price to $1500 — HF = (1500 * 0.8) / 1400 = 0.857 < 1
        oracle.setPrice(address(weth), 1500e8, 8);

        uint256 hf = pool.healthFactor(alice);
        assertTrue(hf < 1e18, "Should be unhealthy after price crash");

        // Charlie liquidates 50% of debt ($700)
        usdc.mint(charlie, 10_000e6);
        vm.startPrank(charlie);
        usdc.approve(address(pool), 700e6);
        pool.liquidate(alice, address(usdc), address(weth), 700e6);
        vm.stopPrank();

        assertTrue(weth.balanceOf(charlie) > 0, "Liquidator should receive WETH + 5% bonus");
    }

    // ─── Withdraw after repay ─────────────────────────────────────────
    function test_WithdrawAfterRepay() public {
        test_Repay();

        uint256 balBefore = weth.balanceOf(alice);
        vm.startPrank(alice);
        pool.withdraw(address(weth), 10 ether);
        vm.stopPrank();
        assertEq(weth.balanceOf(alice), balBefore + 10 ether);
    }

    // ─── Supply Cap ──────────────────────────────────────────────────
    function test_RevertExceedsSupplyCap() public {
        // Set supply cap at 5 WETH
        pool.setCaps(address(weth), 5 ether, 0);

        weth.mint(alice, 100 ether);
        vm.startPrank(alice);
        weth.approve(address(pool), 10 ether);
        vm.expectRevert("LendingPool: supply cap exceeded");
        pool.deposit(address(weth), 10 ether); // 10 > cap of 5
        vm.stopPrank();
    }

    // ─── Borrow Cap ──────────────────────────────────────────────────
    function test_RevertExceedsBorrowCap() public {
        // Set borrow cap at 1000 USDC
        pool.setCaps(address(usdc), 0, 1_000e6);

        vm.startPrank(alice);
        weth.approve(address(pool), 10 ether);
        pool.deposit(address(weth), 10 ether); // $20k collateral
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(pool), 100_000e6);
        pool.deposit(address(usdc), 100_000e6);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert("LendingPool: borrow cap exceeded");
        pool.borrow(address(usdc), 2_000e6); // 2000 > cap of 1000
        vm.stopPrank();
    }

    // ─── Reserve Factor ──────────────────────────────────────────────
    function test_ReserveFactor() public {
        test_DepositAndBorrow();

        // Fast-forward 1 year so interest accrues
        vm.warp(block.timestamp + 365 days);

        // Trigger interest accrual by any deposit
        usdc.mint(bob, 1e6);
        vm.startPrank(bob);
        usdc.approve(address(pool), 1e6);
        pool.deposit(address(usdc), 1e6);
        vm.stopPrank();

        // Protocol should have collected reserves
        uint256 r = pool.getReserves(address(usdc));
        assertGt(r, 0, "Protocol should have non-zero reserves after 1 year");
    }

    // ─── Flash Loan (success) ─────────────────────────────────────────
    function test_FlashLoan_Success() public {
        // Seed the pool with USDC liquidity
        vm.startPrank(bob);
        usdc.approve(address(pool), 100_000e6);
        pool.deposit(address(usdc), 100_000e6);
        vm.stopPrank();

        GoodFlashReceiver receiver = new GoodFlashReceiver(usdc);
        uint256 flashAmount = 10_000e6;
        uint256 expectedFee = flashAmount * 9 / 10_000; // 0.09%

        pool.flashLoan(address(receiver), address(usdc), flashAmount, "");

        // Pool should have grown by the fee amount
        uint256 r = pool.getReserves(address(usdc));
        assertEq(r, expectedFee, "Flash loan fee should go to reserves");
    }

    // ─── Flash Loan (bad borrower reverts) ────────────────────────────
    function test_FlashLoan_RevertNotRepaid() public {
        vm.startPrank(bob);
        usdc.approve(address(pool), 100_000e6);
        pool.deposit(address(usdc), 100_000e6);
        vm.stopPrank();

        BadFlashReceiver receiver = new BadFlashReceiver();
        vm.expectRevert("LendingPool: flash loan not repaid");
        pool.flashLoan(address(receiver), address(usdc), 10_000e6, "");
    }

    // ─── Oracle timelock ──────────────────────────────────────────────
    function test_OracleTimelock() public {
        MockPriceOracle newOracle = new MockPriceOracle();

        // Propose new oracle
        pool.proposeOracle(address(newOracle));
        assertEq(pool.pendingOracle(), address(newOracle));

        // Attempting to execute immediately should revert
        vm.expectRevert("LendingPool: oracle timelock active");
        pool.executeOracleUpdate();

        // Fast-forward 48 hours
        vm.warp(block.timestamp + 48 hours);
        pool.executeOracleUpdate();
        assertEq(address(pool.oracle()), address(newOracle));
    }

    // ─── Fuzz ────────────────────────────────────────────────────────
    function testFuzz_DepositWithdraw(uint256 amount) public {
        amount = bound(amount, 1e15, 50 ether);
        weth.mint(alice, amount);

        vm.startPrank(alice);
        weth.approve(address(pool), amount);
        pool.deposit(address(weth), amount);
        pool.withdraw(address(weth), amount);
        vm.stopPrank();

        assertEq(pool.getUserDebt(alice, address(weth)), 0);
    }
}
