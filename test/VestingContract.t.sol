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
        vm.skip(true);
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
        vesting.initialize(owner, address(ggpVaultMock), address(ggpTokenMock));
        uint256 THREE_MONTHS = 7776000;

        // vm.expectRevert();
        // vesting.stakeOnBehalfOf(randomUser1, 1000e18, 0, THREE_MONTHS, 16);

        ggpTokenMock.approve(address(vesting), 1000e18);

        uint256 intervals = 16;
        uint256 totalVestAmount = 1000e18;
        assertEq(ggpTokenMock.balanceOf(address(vesting)), 0, "Releasable shares for randomUser1 should be 0");

        uint256 adminTokenAmountStarting = ggpTokenMock.balanceOf(address(this));

        vesting.stakeOnBehalfOf(randomUser1, totalVestAmount, 0, 0, THREE_MONTHS, intervals);
        assertEq(
            ggpTokenMock.balanceOf(address(this)),
            adminTokenAmountStarting - totalVestAmount,
            "Releasable shares for randomUser1 should be 0"
        );

        assertEq(ggpTokenMock.balanceOf(address(vesting)), 0, "Releasable shares for randomUser1 should be 0");

        uint256 releasableShares = vesting.getReleasableShares(randomUser1);
        assertEq(releasableShares, 0, "Releasable shares for randomUser1 should be 0");

        vm.startPrank(randomUser1);
        vm.expectRevert();
        vesting.claim();

        vm.warp(block.timestamp + THREE_MONTHS - 1);
        assertGe(vesting.getReleasableShares(randomUser1), 0, "Releasable shares for randomUser1 should be 0");
        vm.expectRevert();
        vesting.claim();

        vm.warp(block.timestamp + THREE_MONTHS);

        assertEq(
            vesting.getReleasableShares(randomUser1), 1000e18 / 16, "Releasable shares for randomUser1 should be 0"
        );
        vm.stopPrank();

        vesting.cancelVesting(randomUser1);

        assertEq(
            ggpTokenMock.balanceOf(address(this)),
            adminTokenAmountStarting,
            "Releasable shares for randomUser1 should be 0"
        );
        assertEq(ggpTokenMock.balanceOf(address(vesting)), 0, "Releasable shares for randomUser1 should be 0");

        assertEq(vesting.getReleasableShares(randomUser1), 0, "Releasable shares for randomUser1 should be 0");
    }
}
