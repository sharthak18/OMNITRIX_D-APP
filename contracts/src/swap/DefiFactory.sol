// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./DefiPair.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title DefiFactory
/// @notice Deploys and tracks all AMM pairs. Inspired by Uniswap v2 Factory.
///         Protocol fee: when feeTo != address(0), 1/6 of all swap fees
///         (0.05% of volume) are minted as LP tokens to feeTo.
contract DefiFactory is Ownable {
    /// @notice Recipient of protocol fees. Set to address(0) to disable.
    address public feeTo;

    /// @notice Only feeToSetter may change feeTo — separates treasury ops from ownership.
    address public feeToSetter;

    event FeeToUpdated(address indexed newFeeTo);
    event FeeToSetterUpdated(address indexed newFeeToSetter);

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 pairIndex);

    constructor(address initialOwner) Ownable(initialOwner) {
        feeToSetter = initialOwner; // owner starts as fee setter
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    /// @notice Create a new token pair. token0 and token1 are sorted.
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "DefiFactory: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "DefiFactory: ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "DefiFactory: PAIR_EXISTS");

        // Deploy pair using CREATE2 for deterministic address
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        pair = address(new DefiPair{salt: salt}());
        DefiPair(pair).initialize(token0, token1);

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // bidirectional lookup
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    /// @notice Set protocol fee recipient (address(0) = fee disabled)
    /// @dev Only callable by feeToSetter — not by owner unless they are feeToSetter
    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "DefiFactory: FORBIDDEN");
        feeTo = _feeTo;
        emit FeeToUpdated(_feeTo);
    }

    /// @notice Transfer the feeToSetter role to another address
    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "DefiFactory: FORBIDDEN");
        require(_feeToSetter != address(0), "DefiFactory: zero address");
        feeToSetter = _feeToSetter;
        emit FeeToSetterUpdated(_feeToSetter);
    }

    /// @notice Compute the deterministic pair address before deployment
    function pairFor(address tokenA, address tokenB) external view returns (address) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(type(DefiPair).creationCode)
        )))));
    }
}
