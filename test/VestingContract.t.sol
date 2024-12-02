// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {VestingContract} from "../src/VestingContract.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {GGPVaultMock} from "./mocks/GGPVaultMock.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract WalletTest is Test {
    VestingContract public vestingContract;
    GGPVaultMock public ggpVaultMock;
    ERC20Mock public ggpTokenMock;
    address owner;

    function setUp() public {
        owner = address(this);
        ggpTokenMock = new ERC20Mock();
        ggpVaultMock = new GGPVaultMock(ggpTokenMock);
        vestingContract = new VestingContract();
        address proxy = Upgrades.deployUUPSProxy(
            "VestingContract.sol",
            abi.encodeCall(vestingContract.initialize, (owner, address(ggpVaultMock), address(ggpTokenMock)))
        );
    }
}
