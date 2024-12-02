// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {VestingContract} from "../contracts/VestingContract.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {GGPVaultMock} from "./mocks/GGPVaultMock.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract VestingContractTest is Test {
    VestingContract public vestingContract;
    GGPVaultMock public ggpVaultMock;
    ERC20Mock public ggpTokenMock;
    address owner;
    VestingContract vesting;

    function setUp() public {
        owner = address(this);
        ggpTokenMock = new ERC20Mock();
        ggpVaultMock = new GGPVaultMock(ggpTokenMock);
        vestingContract = new VestingContract();
        address proxy = Upgrades.deployUUPSProxy(
            "VestingContract.sol",
            abi.encodeCall(vestingContract.initialize, (owner, address(ggpVaultMock), address(ggpTokenMock)))
        );

        vesting = VestingContract(proxy);
    }

    function testWalkThroughEntireScenario() public {
        // Setup roles and addresses
        address nodeOp1 = address(0x999);
        address nodeOp2 = address(0x888);
        address randomUser1 = address(0x777);
        address randomUser2 = address(0x666);
        address randomUser3 = address(0x555);

        // Transfer tokens to users
        ggpTokenMock.transfer(randomUser1, 10000e18);
        ggpTokenMock.transfer(randomUser2, 10000e18);

        // Test re-initialization should revert
        vm.expectRevert();
        vestingContract.initialize(owner, address(ggpVaultMock), address(ggpTokenMock));
    }
}
