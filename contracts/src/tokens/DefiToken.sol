// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title DefiToken
/// @notice Native governance and reward token for the DeFi protocol.
///         Fixed 100M supply minted to deployer; owner can mint for staking rewards.
contract DefiToken is ERC20, ERC20Permit, ERC20Burnable, Ownable {
    uint256 public constant MAX_SUPPLY = 100_000_000 ether; // 100M tokens
    uint256 public totalMinted;

    event Minted(address indexed to, uint256 amount);

    constructor(address initialOwner)
        ERC20("Omnitrix Token", "OMNI")
        ERC20Permit("Omnitrix Token")
        Ownable(initialOwner)
    {
        // Mint 60M to deployer (treasury + liquidity seed)
        _mintChecked(initialOwner, 60_000_000 ether);
    }

    /// @notice Mint additional tokens for staking rewards (up to MAX_SUPPLY)
    function mint(address to, uint256 amount) external onlyOwner {
        _mintChecked(to, amount);
    }

    function _mintChecked(address to, uint256 amount) internal {
        require(totalMinted + amount <= MAX_SUPPLY, "DefiToken: max supply exceeded");
        totalMinted += amount;
        _mint(to, amount);
        emit Minted(to, amount);
    }
}
