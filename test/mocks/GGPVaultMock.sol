// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title GGPVaultMock
/// @dev A simplified ERC-4626 vault implementation for testing deposit and redeem functionality.
contract GGPVaultMock is ERC4626 {
    constructor(IERC20 asset) ERC20("GGP Vault Mock", "xGGP") ERC4626(asset) {}
}
