// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IPriceOracle.sol";

/// @title PriceOracle
/// @notice Wraps Chainlink AggregatorV3 feeds. Owner registers feed addresses per token.
///         Returns price in USD with the feed's native decimals (usually 8).
contract PriceOracle is IPriceOracle, Ownable {
    struct FeedData {
        AggregatorV3Interface feed;
        uint8 decimals;
    }

    mapping(address => FeedData) private _feeds;

    event FeedRegistered(address indexed token, address indexed feed);

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Register a Chainlink price feed for a token
    function registerFeed(address token, address feed) external onlyOwner {
        require(token != address(0), "PriceOracle: zero token");
        require(feed != address(0), "PriceOracle: zero feed");
        uint8 dec = AggregatorV3Interface(feed).decimals();
        _feeds[token] = FeedData(AggregatorV3Interface(feed), dec);
        emit FeedRegistered(token, feed);
    }

    /// @notice Returns latest USD price of token and its decimals
    function getPrice(address token) external view override returns (uint256 price, uint8 decimals) {
        FeedData memory fd = _feeds[token];
        require(address(fd.feed) != address(0), "PriceOracle: feed not found");

        (, int256 answer, , uint256 updatedAt,) = fd.feed.latestRoundData();
        require(answer > 0, "PriceOracle: invalid price");
        require(block.timestamp - updatedAt <= 3600, "PriceOracle: stale price"); // 1h freshness

        price = uint256(answer);
        decimals = fd.decimals;
    }

    /// @notice Convenience: get price normalized to 18 decimals
    function getPriceNormalized(address token) external view returns (uint256) {
        (uint256 price, uint8 dec) = this.getPrice(token);
        return price * 10 ** (18 - dec);
    }
}
