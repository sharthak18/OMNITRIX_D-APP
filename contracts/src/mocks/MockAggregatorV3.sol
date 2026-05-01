// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// SPDX compatible Chainlink mock aggregator for local testing
contract MockAggregatorV3 {
    uint8   public decimals;
    int256  public latestAnswer;
    uint256 public latestTimestamp;
    uint80  private _roundId;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals      = _decimals;
        latestAnswer  = _initialAnswer;
        latestTimestamp = block.timestamp;
        _roundId      = 1;
    }

    function updateAnswer(int256 _answer) external {
        latestAnswer    = _answer;
        latestTimestamp = block.timestamp;
        _roundId++;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80  roundId,
            int256  answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80  answeredInRound
        )
    {
        return (_roundId, latestAnswer, latestTimestamp, latestTimestamp, _roundId);
    }

    function getRoundData(uint80)
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (_roundId, latestAnswer, latestTimestamp, latestTimestamp, _roundId);
    }

    function description() external pure returns (string memory) { return "Mock / USD"; }
    function version()     external pure returns (uint256) { return 4; }
}
