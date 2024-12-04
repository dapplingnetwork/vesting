// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {VestingContract} from "../contracts/VestingContract.sol";
import {GGPVaultMock} from "./mocks/GGPVaultMock.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract VestingContractTest is Test {
    VestingContract public vestingContract;
    GGPVaultMock public ggpVaultMock;
    ERC20Mock public ggpTokenMock;
    address public owner;
    address public vestingManager;
    address public beneficiary;

    function setUp() public {
        // Initialize mock contracts
        owner = address(this);
        vestingManager = address(0x1);
        beneficiary = address(0x2);

        ggpTokenMock = new ERC20Mock();
        ggpVaultMock = new GGPVaultMock(ggpTokenMock);

        // Deploy VestingContract as a UUPS proxy
        VestingContract implementation = new VestingContract();
        address proxy = Upgrades.deployUUPSProxy(
            "VestingContract.sol",
            abi.encodeCall(implementation.initialize, (owner, address(ggpVaultMock), address(ggpTokenMock)))
        );

        vestingContract = VestingContract(proxy);

        // Grant vesting manager role
        vestingContract.grantRole(vestingContract.VESTING_MANAGER_ROLE(), vestingManager);

        // transfer tokens to the vesting manager
        ggpTokenMock.transfer(vestingManager, 1_000_000 ether);
    }

    function testStakeOnBehalfOf() public {
        uint256 totalAmount = 1_000 ether;
        uint256 vestedAmount = 0 ether;
        uint256 cliffDuration = 180 days;
        uint256 intervalDuration = 90 days;
        uint256 totalIntervals = 4;

        // Approve and call `stakeOnBehalfOf`
        vm.prank(vestingManager);
        ggpTokenMock.approve(address(vestingContract), totalAmount);

        vm.prank(vestingManager);
        vestingContract.stakeOnBehalfOf(
            beneficiary,
            totalAmount,
            vestedAmount,
            cliffDuration,
            intervalDuration,
            totalIntervals
        );

        // Validate vesting details
        (
            uint256 totalShares,
            uint256 releasedShares,
            uint256 actualVestedAmount,
            uint256 startTime,
            uint256 endTime,
            uint256 cliffTime,
            uint256 vestingIntervals,
            bool isActive
        ) = vestingContract.vestingInfo(beneficiary);

        assertEq(totalShares, totalAmount - vestedAmount, "Incorrect total shares");
        assertEq(actualVestedAmount, vestedAmount, "Incorrect vested amount");
        assertEq(cliffTime, startTime + cliffDuration, "Incorrect cliff time");
        assertEq(endTime, startTime + intervalDuration * totalIntervals, "Incorrect end time");
        assertEq(vestingIntervals, totalIntervals, "Incorrect number of intervals");
        assertEq(isActive, true, "Vesting should be active");
    }

    function testStakeOnBehalfOf_InvalidInputs() public {
        uint256 totalAmount = 1_000 ether;

        vm.prank(vestingManager);
        ggpTokenMock.approve(address(vestingContract), totalAmount);

        vm.startPrank(vestingManager);

        vm.expectRevert("Amount must be greater than zero");
        vestingContract.stakeOnBehalfOf(beneficiary, 0, 0, 0, 90 days, 4);

        vm.expectRevert("Intervals must be greater than zero");
        vestingContract.stakeOnBehalfOf(beneficiary, totalAmount, 0, 0, 90 days, 0);

        vm.expectRevert("Vested amount cannot exceed total amount");
        vestingContract.stakeOnBehalfOf(beneficiary, totalAmount, totalAmount + 1 ether, 0, 90 days, 4);
    }
function testStakeOnBehalfOf_ExistingVesting() public {
    uint256 totalAmount = 1_000 ether;
    uint256 vestedAmount = 0 ether;
    uint256 cliffDuration = 180 days;
    uint256 intervalDuration = 90 days;
    uint256 totalIntervals = 4;

    // Approve and stake for the first vesting
    vm.prank(vestingManager);
    ggpTokenMock.approve(address(vestingContract), totalAmount);

    vm.prank(vestingManager);
    vestingContract.stakeOnBehalfOf(
        beneficiary,
        totalAmount,
        vestedAmount,
        cliffDuration,
        intervalDuration,
        totalIntervals
    );

    // Attempt to stake again for the same beneficiary (should revert)
    vm.prank(vestingManager);
    vm.expectRevert("Existing vesting already active");
    vestingContract.stakeOnBehalfOf(
        beneficiary,
        totalAmount,
        vestedAmount,
        cliffDuration,
        intervalDuration,
        totalIntervals
    );

    // Cancel the vesting
    vm.prank(owner);
    vestingContract.cancelVesting(beneficiary);

    // Verify vesting is canceled but amounts remain
    (
        uint256 totalShares,
        uint256 releasedShares,
        uint256 actualVestedAmount,
        uint256 startTime,
        uint256 endTime,
        uint256 cliffTime,
        uint256 vestingIntervals,
        bool isActive
    ) = vestingContract.vestingInfo(beneficiary);

    assertEq(isActive, false, "Vesting should be inactive after cancellation");
    assertEq(totalShares, totalAmount - vestedAmount, "Total shares should remain after cancellation");
    assertEq(actualVestedAmount, vestedAmount, "Vested amount should remain after cancellation");
    assertEq(releasedShares, 0, "Released shares should still be zero after cancellation");

    // Retry staking a new vesting for the same beneficiary
    vm.prank(vestingManager);
    ggpTokenMock.approve(address(vestingContract), totalAmount);

    vm.prank(vestingManager);
    vestingContract.stakeOnBehalfOf(
        beneficiary,
        totalAmount,
        vestedAmount,
        cliffDuration,
        intervalDuration,
        totalIntervals
    );

    // Validate the new vesting details
    (
        totalShares,
        releasedShares,
        actualVestedAmount,
        startTime,
        endTime,
        cliffTime,
        vestingIntervals,
        isActive
    ) = vestingContract.vestingInfo(beneficiary);

    assertEq(totalShares, totalAmount - vestedAmount, "Incorrect total shares in new vesting");
    assertEq(actualVestedAmount, vestedAmount, "Incorrect vested amount in new vesting");
    assertEq(cliffTime, startTime + cliffDuration, "Incorrect cliff time in new vesting");
    assertEq(endTime, startTime + intervalDuration * totalIntervals, "Incorrect end time in new vesting");
    assertEq(vestingIntervals, totalIntervals, "Incorrect intervals in new vesting");
    assertEq(isActive, true, "Vesting should be active in new vesting");
}

function testMultipleBeneficiaries() public {
    address beneficiary1 = address(0x3);
    address beneficiary2 = address(0x4);

    uint256 totalAmount1 = 1_000 ether;
    uint256 vestedAmount1 = 0 ether;
    uint256 cliffDuration1 = 180 days;
    uint256 intervalDuration1 = 90 days;
    uint256 totalIntervals1 = 4;

    uint256 totalAmount2 = 2_000 ether;
    uint256 vestedAmount2 = 0 ether;
    uint256 cliffDuration2 = 180 days;
    uint256 intervalDuration2 = 180 days;
    uint256 totalIntervals2 = 8;

    // Approve and stake for beneficiary1
    vm.prank(vestingManager);
    ggpTokenMock.approve(address(vestingContract), totalAmount1);

    vm.prank(vestingManager);
    vestingContract.stakeOnBehalfOf(
        beneficiary1,
        totalAmount1,
        vestedAmount1,
        cliffDuration1,
        intervalDuration1,
        totalIntervals1
    );

    // Approve and stake for beneficiary2
    vm.prank(vestingManager);
    ggpTokenMock.approve(address(vestingContract), totalAmount2);

    vm.prank(vestingManager);
    vestingContract.stakeOnBehalfOf(
        beneficiary2,
        totalAmount2,
        vestedAmount2,
        cliffDuration2,
        intervalDuration2,
        totalIntervals2
    );

    // Validate vesting for beneficiary1
    (
        uint256 totalShares1,
        uint256 releasedShares1,
        uint256 actualVestedAmount1,
        uint256 startTime1,
        uint256 endTime1,
        uint256 cliffTime1,
        uint256 vestingIntervals1,
        bool isActive1
    ) = vestingContract.vestingInfo(beneficiary1);

    assertEq(totalShares1, totalAmount1 - vestedAmount1, "Incorrect total shares for beneficiary1");
    assertEq(actualVestedAmount1, vestedAmount1, "Incorrect vested amount for beneficiary1");
    assertEq(cliffTime1, startTime1 + cliffDuration1, "Incorrect cliff time for beneficiary1");
    assertEq(endTime1, startTime1 + intervalDuration1 * totalIntervals1, "Incorrect end time for beneficiary1");
    assertEq(vestingIntervals1, totalIntervals1, "Incorrect intervals for beneficiary1");
    assertEq(isActive1, true, "Vesting should be active for beneficiary1");

    // Validate vesting for beneficiary2
    (
        uint256 totalShares2,
        uint256 releasedShares2,
        uint256 actualVestedAmount2,
        uint256 startTime2,
        uint256 endTime2,
        uint256 cliffTime2,
        uint256 vestingIntervals2,
        bool isActive2
    ) = vestingContract.vestingInfo(beneficiary2);

    assertEq(totalShares2, totalAmount2 - vestedAmount2, "Incorrect total shares for beneficiary2");
    assertEq(actualVestedAmount2, vestedAmount2, "Incorrect vested amount for beneficiary2");
    assertEq(cliffTime2, startTime2 + cliffDuration2, "Incorrect cliff time for beneficiary2");
    assertEq(endTime2, startTime2 + intervalDuration2 * totalIntervals2, "Incorrect end time for beneficiary2");
    assertEq(vestingIntervals2, totalIntervals2, "Incorrect intervals for beneficiary2");
    assertEq(isActive2, true, "Vesting should be active for beneficiary2");

    // Ensure vestings are independent
    assertTrue(beneficiary1 != beneficiary2, "Beneficiaries should be independent");
    assertTrue(totalShares1 != totalShares2, "Shares for each beneficiary should be independent");
    assertTrue(cliffTime1 != cliffTime2, "Cliff times for each beneficiary should be independent");
}

function testStakeOnBehalfOf_CliffPeriod() public {
    address beneficiary = address(0x3);

    uint256 totalAmount = 1_000 ether;
    uint256 vestedAmount = 0 ether; // Already vested amount
    uint256 cliffDuration = 180 days;
    uint256 intervalDuration = 90 days;
    uint256 totalIntervals = 4;

    // Approve and stake for the beneficiary
    vm.prank(vestingManager);
    ggpTokenMock.approve(address(vestingContract), totalAmount);

    vm.prank(vestingManager);
    vestingContract.stakeOnBehalfOf(
        beneficiary,
        totalAmount,
        vestedAmount,
        cliffDuration,
        intervalDuration,
        totalIntervals
    );

    // Validate initial state
    (
        uint256 totalShares,
        uint256 releasedShares,
        uint256 actualVestedAmount,
        uint256 startTime,
        uint256 endTime,
        uint256 cliffTime,
        uint256 vestingIntervals,
        bool isActive
    ) = vestingContract.vestingInfo(beneficiary);

    assertEq(actualVestedAmount, vestedAmount, "Incorrect initial vested amount");
    assertEq(isActive, true, "Vesting should be active");
    assertEq(cliffTime, startTime + cliffDuration, "Incorrect cliff time");

    // Fast forward to just before the cliff period
    vm.warp(cliffTime - 1);
    uint256 releasableSharesBeforeCliff = vestingContract.getReleasableShares(beneficiary);
    assertEq(releasableSharesBeforeCliff, 0, "No shares should be releasable before the cliff");

    // Fast forward to the cliff period
    vm.warp(cliffTime);
    uint256 releasableSharesAtCliff = vestingContract.getReleasableShares(beneficiary);
    assertTrue(releasableSharesAtCliff > 0, "Shares should be releasable at the cliff time");

    // Claim the assets after the cliff
    vm.prank(beneficiary);
    vestingContract.claim();

    (
        uint256 totalSharesAfterClaim,
        uint256 releasedSharesAfterClaim,
        uint256 actualVestedAmountAfterClaim,
        uint256 startTimeAfterClaim,
        uint256 endTimeAfterClaim,
        uint256 cliffTimeAfterClaim,
        uint256 vestingIntervalsAfterClaim,
        bool isActiveAfterClaim
    ) = vestingContract.vestingInfo(beneficiary);

    assertEq(
        releasedSharesAfterClaim,
        releasableSharesAtCliff,
        "Released shares should match the releasable shares after claim"
    );
    assertEq(actualVestedAmountAfterClaim, 0, "Vested amount should be zero after claiming");
}



}
