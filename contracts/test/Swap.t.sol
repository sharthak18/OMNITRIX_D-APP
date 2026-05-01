// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/tokens/DefiToken.sol";
import "../src/swap/DefiFactory.sol";
import "../src/swap/DefiPair.sol";
import "../src/swap/DefiRouter.sol";
import "../src/mocks/MockERC20.sol";

contract SwapTest is Test {
    DefiToken   public defi;
    MockERC20   public usdc;
    DefiFactory public factory;
    DefiRouter  public router;
    DefiPair    public pair;

    address alice = makeAddr("alice");
    address bob   = makeAddr("bob");

    uint256 constant INITIAL_DEFI = 1_000_000 ether;
    uint256 constant INITIAL_USDC = 2_000_000e6; // 6 decimals

    function setUp() public {
        defi    = new DefiToken(address(this));
        usdc    = new MockERC20("USD Coin", "USDC", 6);
        factory = new DefiFactory(address(this));
        router  = new DefiRouter(address(factory));

        // Mint tokens to alice
        defi.transfer(alice, INITIAL_DEFI);
        usdc.mint(alice, INITIAL_USDC);
        defi.transfer(bob, 10_000 ether);
    }

    function test_CreatePair() public {
        address pairAddr = factory.createPair(address(defi), address(usdc));
        assertTrue(pairAddr != address(0));
        assertEq(factory.getPair(address(defi), address(usdc)), pairAddr);
        assertEq(factory.getPair(address(usdc), address(defi)), pairAddr); // bidirectional
        assertEq(factory.allPairsLength(), 1);
    }

    function test_RevertCreateDuplicatePair() public {
        factory.createPair(address(defi), address(usdc));
        vm.expectRevert("DefiFactory: PAIR_EXISTS");
        factory.createPair(address(defi), address(usdc));
    }

    function _addLiquidity(address user, uint256 amountDefi, uint256 amountUsdc) internal {
        vm.startPrank(user);
        defi.approve(address(router), amountDefi);
        usdc.approve(address(router), amountUsdc);
        router.addLiquidity(
            address(defi),
            address(usdc),
            amountDefi,
            amountUsdc,
            0, 0,
            user,
            block.timestamp + 1
        );
        vm.stopPrank();
    }

    function test_AddLiquidity() public {
        _addLiquidity(alice, 100_000 ether, 200_000e6);

        address pairAddr = factory.getPair(address(defi), address(usdc));
        DefiPair p = DefiPair(pairAddr);

        (uint112 r0, uint112 r1,) = p.getReserves();
        assertTrue(r0 > 0 && r1 > 0);
        assertTrue(p.balanceOf(alice) > 0);
    }

    function test_SwapExactIn() public {
        _addLiquidity(alice, 100_000 ether, 200_000e6);

        uint256 swapAmount = 1_000 ether; // swap 1000 DEFI

        vm.startPrank(bob);
        defi.approve(address(router), swapAmount);

        address[] memory path = new address[](2);
        path[0] = address(defi);
        path[1] = address(usdc);

        uint256 usdcBefore = usdc.balanceOf(bob);
        router.swapExactTokensForTokens(swapAmount, 0, path, bob, block.timestamp + 1);
        uint256 usdcAfter = usdc.balanceOf(bob);

        assertTrue(usdcAfter > usdcBefore, "bob should receive USDC");
        vm.stopPrank();
    }

    function test_SwapRespectsFee() public {
        _addLiquidity(alice, 100_000 ether, 100_000e6); // 1:1 pool

        uint256 swapAmount = 1_000 ether;
        (uint256 reserveIn, uint256 reserveOut) = router.quote(1e18, 1e18, 1e18) > 0
            ? (100_000 ether, 100_000e6)
            : (100_000 ether, 100_000e6);

        uint256 expectedOut = router.getAmountOut(swapAmount, reserveIn, reserveOut);
        // Should be less than raw amount due to 0.3% fee
        assertTrue(expectedOut < swapAmount * 100_000e6 / 100_000 ether);
    }

    function test_RemoveLiquidity() public {
        _addLiquidity(alice, 100_000 ether, 200_000e6);

        address pairAddr = factory.getPair(address(defi), address(usdc));
        DefiPair p = DefiPair(pairAddr);
        uint256 lpBalance = p.balanceOf(alice);

        vm.startPrank(alice);
        p.approve(address(router), lpBalance);
        (uint256 a0, uint256 a1) = router.removeLiquidity(
            address(defi), address(usdc), lpBalance, 0, 0, alice, block.timestamp + 1
        );
        vm.stopPrank();

        assertTrue(a0 > 0 && a1 > 0);
        assertEq(p.balanceOf(alice), 0);
    }

    function testFuzz_SwapAmounts(uint256 amountIn) public {
        amountIn = bound(amountIn, 1 ether, 10_000 ether);
        _addLiquidity(alice, 100_000 ether, 200_000e6);

        vm.startPrank(bob);
        defi.approve(address(router), amountIn);
        address[] memory path = new address[](2);
        path[0] = address(defi);
        path[1] = address(usdc);
        uint256[] memory amounts = router.getAmountsOut(amountIn, path);
        assertTrue(amounts[1] > 0);
        vm.stopPrank();
    }
}
