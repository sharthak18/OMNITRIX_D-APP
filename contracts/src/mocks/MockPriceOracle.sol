// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../lending/IPriceOracle.sol";

/// @notice Mock price oracle for testing — owner sets prices manually
contract MockPriceOracle is IPriceOracle {
    struct MockPrice {
        uint256 price;
        uint8   decimals;
    }

    mapping(address => MockPrice) private _prices;
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function setPrice(address token, uint256 price, uint8 dec) external {
        require(msg.sender == owner, "MockOracle: not owner");
        _prices[token] = MockPrice(price, dec);
    }

    function getPrice(address token) external view override returns (uint256 price, uint8 decimals) {
        MockPrice storage p = _prices[token];
        require(p.price > 0, "MockOracle: price not set");
        return (p.price, p.decimals);
    }
}
