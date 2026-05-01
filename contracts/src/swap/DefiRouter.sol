// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./DefiPair.sol";
import "./DefiFactory.sol";

/// @title DefiRouter
/// @notice High-level router for adding/removing liquidity and executing swaps.
///         Includes slippage protection, deadline enforcement, and reentrancy
///         protection against ERC-777-style callback tokens.
contract DefiRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable factory;

    event LiquidityAdded(address tokenA, address tokenB, uint256 amountA, uint256 amountB, uint256 liquidity, address to);
    event LiquidityRemoved(address tokenA, address tokenB, uint256 amountA, uint256 amountB, address to);

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "DefiRouter: EXPIRED");
        _;
    }

    constructor(address _factory) {
        factory = _factory;
    }

    /* ──────────────────── Internal helpers ──────────────────── */

    function _getPair(address tokenA, address tokenB) internal view returns (address) {
        address pair = DefiFactory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "DefiRouter: PAIR_NOT_FOUND");
        return pair;
    }

    function _getReserves(address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0,) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        (uint112 reserve0, uint112 reserve1,) = DefiPair(_getPair(tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function _quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256) {
        require(amountA > 0, "DefiRouter: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "DefiRouter: INSUFFICIENT_LIQUIDITY");
        return amountA * reserveB / reserveA;
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "DefiRouter: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "DefiRouter: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "DefiRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "DefiRouter: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = numerator / denominator + 1;
    }

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        // Create pair if not exists
        if (DefiFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            DefiFactory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = _getReserves(tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = _quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "DefiRouter: INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = _quote(amountBDesired, reserveB, reserveA);
                require(amountAOptimal <= amountADesired, "DefiRouter: EXCESSIVE_A_AMOUNT");
                require(amountAOptimal >= amountAMin, "DefiRouter: INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    /* ──────────────────── Public views ──────────────────── */

    /// @notice Get quote for token amounts when adding liquidity
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256) {
        return _quote(amountA, reserveA, reserveB);
    }

    /// @notice Get output amount for a given input (with 0.3% fee)
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        external pure returns (uint256)
    {
        return _getAmountOut(amountIn, reserveIn, reserveOut);
    }

    /// @notice Get input amount required for a given output (with 0.3% fee)
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        external pure returns (uint256)
    {
        return _getAmountIn(amountOut, reserveIn, reserveOut);
    }

    /// @notice Get output amounts for a multi-hop path
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external view returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "DefiRouter: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = _getReserves(path[i], path[i + 1]);
            amounts[i + 1] = _getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    /* ──────────────────── Add Liquidity ──────────────────── */

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = _getPair(tokenA, tokenB);
        IERC20(tokenA).safeTransferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, pair, amountB);
        liquidity = DefiPair(pair).mint(to);
        emit LiquidityAdded(tokenA, tokenB, amountA, amountB, liquidity, to);
    }

    /* ──────────────────── Remove Liquidity ──────────────────── */

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = _getPair(tokenA, tokenB);
        IERC20(pair).safeTransferFrom(msg.sender, pair, liquidity);
        (uint256 amount0, uint256 amount1) = DefiPair(pair).burn(to);
        (address token0,) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "DefiRouter: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "DefiRouter: INSUFFICIENT_B_AMOUNT");
        emit LiquidityRemoved(tokenA, tokenB, amountA, amountB, to);
    }

    /* ──────────────────── Swap ──────────────────── */

    function _swap(uint256[] memory amounts, address[] calldata path, address to) internal {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = input < output ? (input, output) : (output, input);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address receiver = i < path.length - 2
                ? DefiFactory(factory).getPair(output, path[i + 2])
                : to;
            DefiPair(DefiFactory(factory).getPair(input, output)).swap(amount0Out, amount1Out, receiver);
        }
    }

    /// @notice Swap exact input for at-least amountOutMin output
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256[] memory amounts) {
        require(path.length >= 2, "DefiRouter: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = _getReserves(path[i], path[i + 1]);
            amounts[i + 1] = _getAmountOut(amounts[i], reserveIn, reserveOut);
        }
        require(amounts[amounts.length - 1] >= amountOutMin, "DefiRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        IERC20(path[0]).safeTransferFrom(msg.sender, DefiFactory(factory).getPair(path[0], path[1]), amountIn);
        _swap(amounts, path, to);
    }

    /// @notice Swap at-most amountInMax input for exact output
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256[] memory amounts) {
        require(path.length >= 2, "DefiRouter: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = _getReserves(path[i - 1], path[i]);
            amounts[i - 1] = _getAmountIn(amounts[i], reserveIn, reserveOut);
        }
        require(amounts[0] <= amountInMax, "DefiRouter: EXCESSIVE_INPUT_AMOUNT");
        IERC20(path[0]).safeTransferFrom(msg.sender, DefiFactory(factory).getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }
}
