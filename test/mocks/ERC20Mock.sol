// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title SimpleERC20Token
/// @dev A basic ERC20 token implementation.
contract ERC20Mock is ERC20 {
    constructor() ERC20("GoGoPool Token", "GGP") {
        // Mint an initial supply to the deployer
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }
}
