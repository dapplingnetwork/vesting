// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/finance/VestingWallet.sol";

contract Wallet is VestingWallet {
    constructor(address beneficiary, uint64 startTimestamp, uint64 durationSeconds)
        VestingWallet(beneficiary, startTimestamp, durationSeconds)
    {}
}
