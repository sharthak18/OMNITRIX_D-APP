// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/staking/StakingRewards.sol";
import "../src/tokens/DefiToken.sol";
import "../src/mocks/MockERC20.sol";

contract StakingTest is Test {
    StakingRewards public staking;
    DefiToken      public defi;    // rewards token
    MockERC20      public lpToken; // staking token

    address alice = makeAddr("alice");
    address bob   = makeAddr("bob");

    uint256 constant REWARD_AMOUNT   = 10_000 ether;
    uint256 constant REWARDS_DURATION = 7 days;

    function setUp() public {
        defi    = new DefiToken(address(this));
        lpToken = new MockERC20("LP Token", "LP", 18);
        staking = new StakingRewards(address(defi), address(lpToken), address(this));

        // Mint LP tokens to users
        lpToken.mint(alice, 1_000 ether);
        lpToken.mint(bob,   1_000 ether);

        // Fund rewards
        defi.approve(address(staking), REWARD_AMOUNT);
        staking.notifyRewardAmount(REWARD_AMOUNT);
    }

    function test_Stake() public {
        vm.startPrank(alice);
        lpToken.approve(address(staking), 100 ether);
        staking.stake(100 ether);
        vm.stopPrank();

        assertEq(staking.balanceOf(alice), 100 ether);
        assertEq(staking.totalSupply(),    100 ether);
    }

    function test_RevertStakeZero() public {
        vm.startPrank(alice);
        vm.expectRevert("StakingRewards: cannot stake 0");
        staking.stake(0);
        vm.stopPrank();
    }

    function test_EarnRewards() public {
        vm.startPrank(alice);
        lpToken.approve(address(staking), 100 ether);
        staking.stake(100 ether);
        vm.stopPrank();

        // Fast forward half the rewards duration
        vm.warp(block.timestamp + REWARDS_DURATION / 2);

        uint256 earned = staking.earned(alice);
        assertTrue(earned > 0, "Should have earned rewards");
        // Roughly 5000 DEFI (half the reward over half the period)
        assertApproxEqRel(earned, REWARD_AMOUNT / 2, 0.01e18); // 1% tolerance
    }

    function test_GetReward() public {
        vm.startPrank(alice);
        lpToken.approve(address(staking), 100 ether);
        staking.stake(100 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + REWARDS_DURATION);

        uint256 earned = staking.earned(alice);
        assertTrue(earned > 0);

        vm.prank(alice);
        staking.getReward();

        assertEq(defi.balanceOf(alice), earned);
        assertEq(staking.earned(alice), 0);
    }

    function test_ProRataRewards() public {
        // Alice stakes first, then bob joins halfway through
        vm.startPrank(alice);
        lpToken.approve(address(staking), 100 ether);
        staking.stake(100 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + REWARDS_DURATION / 2);

        vm.startPrank(bob);
        lpToken.approve(address(staking), 100 ether);
        staking.stake(100 ether); // Same amount — splits rewards 50/50 in 2nd half
        vm.stopPrank();

        vm.warp(block.timestamp + REWARDS_DURATION / 2);

        uint256 aliceEarned = staking.earned(alice);
        uint256 bobEarned   = staking.earned(bob);

        // Alice earned ~75% (100% first half + 50% second half), bob ~25%
        assertTrue(aliceEarned > bobEarned, "Alice should earn more");
    }

    function test_Withdraw() public {
        vm.startPrank(alice);
        lpToken.approve(address(staking), 100 ether);
        staking.stake(100 ether);
        staking.withdraw(100 ether);
        vm.stopPrank();

        assertEq(staking.balanceOf(alice), 0);
        assertEq(lpToken.balanceOf(alice),  1_000 ether);
    }

    function test_Exit() public {
        vm.startPrank(alice);
        lpToken.approve(address(staking), 100 ether);
        staking.stake(100 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + REWARDS_DURATION);

        vm.prank(alice);
        staking.exit();

        assertEq(staking.balanceOf(alice), 0);
        assertEq(lpToken.balanceOf(alice),  1_000 ether);
        assertTrue(defi.balanceOf(alice) > 0);
    }

    function test_NewRewardPeriod() public {
        vm.warp(block.timestamp + REWARDS_DURATION + 1);

        uint256 newReward = 5_000 ether;
        defi.approve(address(staking), newReward);
        staking.notifyRewardAmount(newReward);

        assertEq(staking.rewardRate(), newReward / REWARDS_DURATION);
    }

    function testFuzz_StakeWithdraw(uint256 amount) public {
        amount = bound(amount, 1 ether, 1_000 ether);
        lpToken.mint(alice, amount);

        vm.startPrank(alice);
        lpToken.approve(address(staking), amount);
        staking.stake(amount);
        vm.warp(block.timestamp + 1 days);
        staking.exit();
        vm.stopPrank();

        assertTrue(lpToken.balanceOf(alice) >= amount);
    }
}
