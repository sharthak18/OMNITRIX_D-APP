// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPriceOracle
/// @notice Interface for the protocol price oracle
interface IPriceOracle {
    function getPrice(address token) external view returns (uint256 price, uint8 decimals);
}
