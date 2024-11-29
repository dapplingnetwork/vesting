// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.20;

import {VestingContract} from "../../contracts/VestingContract.sol";

/// @custom:oz-upgrades-from VestingContract
contract VestingContractV2 is VestingContract {
    function newMethod() public pure returns (string memory) {
        return "meow";
    }
}
