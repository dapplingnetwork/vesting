// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {VestingContract} from "../contracts/VestingContract.sol";
import {VestingContractV2} from "./mocks/VestingContractV2.sol";
import {GGPVaultMock} from "./mocks/GGPVaultMock.sol";

import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract VestingContractFullTest is Test {
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
            beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
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
            bool isActive,
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

        // Case 1: Amount must be greater than zero
        vm.expectRevert("Amount must be greater than zero");
        vestingContract.stakeOnBehalfOf(beneficiary, 0, 0, 0, 90 days, 4);

        // Case 2: Intervals must be greater than zero
        vm.expectRevert("Intervals must be greater than zero");
        vestingContract.stakeOnBehalfOf(beneficiary, totalAmount, 0, 0, 90 days, 0);

        // Case 3: Vested amount cannot exceed total amount
        vm.expectRevert("Vested amount cannot exceed total amount");
        vestingContract.stakeOnBehalfOf(beneficiary, totalAmount, totalAmount + 1 ether, 0, 90 days, 4);

        // Case 4: Cliff duration exceeds total vesting period
        vm.expectRevert("Cliff duration exceeds total vesting period");
        vestingContract.stakeOnBehalfOf(beneficiary, totalAmount, 0, 365 days * 5, 90 days, 4);

        // Case 5: Cliff duration is non-zero but vested amount is not zero
        vm.expectRevert("Vested amount must be zero if cliff duration is specified");
        vestingContract.stakeOnBehalfOf(beneficiary, totalAmount, 1 ether, 90 days, 90 days, 4);

        // Case 6: Cliff duration must be >= interval duration
        vm.expectRevert("Cliff duration must be >= interval duration");
        vestingContract.stakeOnBehalfOf(beneficiary, totalAmount, 0, 30 days, 90 days, 4);

        vm.stopPrank();
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
            beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
        );

        // Attempt to stake again for the same beneficiary (should revert)
        vm.prank(vestingManager);
        vm.expectRevert("Existing vesting already active");
        vestingContract.stakeOnBehalfOf(
            beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
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
            bool isActive,
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
            beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
        );

        // Validate the new vesting details
        (totalShares, releasedShares, actualVestedAmount, startTime, endTime, cliffTime, vestingIntervals, isActive,) =
            vestingContract.vestingInfo(beneficiary);

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
        uint256 cliffDuration2 = 0 days;
        uint256 intervalDuration2 = 180 days;
        uint256 totalIntervals2 = 8;

        // Approve and stake for beneficiary1
        vm.prank(vestingManager);
        ggpTokenMock.approve(address(vestingContract), totalAmount1);

        vm.prank(vestingManager);
        vestingContract.stakeOnBehalfOf(
            beneficiary1, totalAmount1, vestedAmount1, cliffDuration1, intervalDuration1, totalIntervals1
        );

        // Approve and stake for beneficiary2
        vm.prank(vestingManager);
        ggpTokenMock.approve(address(vestingContract), totalAmount2);

        vm.prank(vestingManager);
        vestingContract.stakeOnBehalfOf(
            beneficiary2, totalAmount2, vestedAmount2, cliffDuration2, intervalDuration2, totalIntervals2
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
            bool isActive1,
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
            bool isActive2,
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
            beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
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
            bool isActive,
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
            bool isActiveAfterClaim,
        ) = vestingContract.vestingInfo(beneficiary);

        assertEq(
            releasedSharesAfterClaim,
            releasableSharesAtCliff,
            "Released shares should match the releasable shares after claim"
        );
        assertEq(actualVestedAmountAfterClaim, 0, "Vested amount should be zero after claiming");
    }

    function testCliffBehavior() public {
        address beneficiary = address(0x4);

        uint256 totalAmount = 1_000 ether;
        uint256 vestedAmount = 0 ether;
        uint256 cliffDuration = 180 days;
        uint256 intervalDuration = 90 days;
        uint256 totalIntervals = 4;

        // Approve and stake for the beneficiary
        vm.prank(vestingManager);
        ggpTokenMock.approve(address(vestingContract), totalAmount);

        vm.prank(vestingManager);
        vestingContract.stakeOnBehalfOf(
            beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
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
            bool isActive,
        ) = vestingContract.vestingInfo(beneficiary);

        assertEq(actualVestedAmount, vestedAmount, "Incorrect initial vested amount");
        assertEq(isActive, true, "Vesting should be active");
        assertEq(cliffTime, startTime + cliffDuration, "Incorrect cliff time");

        // Test before the cliff period
        vm.warp(cliffTime - 1);
        uint256 releasableSharesBeforeCliff = vestingContract.getReleasableShares(beneficiary);
        assertEq(releasableSharesBeforeCliff, 0, "No shares should be releasable before the cliff");

        // Test at the cliff period
        vm.warp(cliffTime);
        uint256 releasableSharesAtCliff = vestingContract.getReleasableShares(beneficiary);
        uint256 intervalsElapsedAtCliff = cliffDuration / intervalDuration; // How many intervals have elapsed at the cliff
        uint256 expectedSharesAtCliff = (totalAmount * intervalsElapsedAtCliff) / totalIntervals;
        assertEq(releasableSharesAtCliff, expectedSharesAtCliff, "Incorrect shares releasable at the cliff");

        // Test claiming at the cliff
        vm.prank(beneficiary);
        vestingContract.claim();
        (
            uint256 totalSharesAfterCliff,
            uint256 releasedSharesAfterCliff,
            uint256 actualVestedAmountAfterCliff,
            uint256 startTimeAfterCliff,
            uint256 endTimeAfterCliff,
            uint256 cliffTimeAfterCliff,
            uint256 vestingIntervalsAfterCliff,
            bool isActiveAfterCliff,
        ) = vestingContract.vestingInfo(beneficiary);

        assertEq(
            releasedSharesAfterCliff,
            releasableSharesAtCliff,
            "Released shares should match the releasable shares at the cliff"
        );
        assertEq(actualVestedAmountAfterCliff, 0, "Vested amount should remain unchanged after claiming");
        assertEq(isActiveAfterCliff, true, "Vesting should remain active after claiming");

        // Test between cliff and next interval
        vm.warp(cliffTime + intervalDuration / 2);
        uint256 releasableSharesMidInterval = vestingContract.getReleasableShares(beneficiary);
        assertGe(releasableSharesMidInterval, 0, "No additional shares should unlock mid-interval");

        // Test at the next interval
        vm.warp(cliffTime + intervalDuration);
        uint256 releasableSharesNextInterval = vestingContract.getReleasableShares(beneficiary);
        uint256 expectedSharesNextInterval = (totalAmount * (intervalsElapsedAtCliff + 1)) / totalIntervals;

        assertEq(
            releasableSharesNextInterval,
            expectedSharesNextInterval - releasedSharesAfterCliff,
            "Incorrect shares releasable at the next interval"
        );

        // Claim at the next interval
        vm.prank(beneficiary);
        vestingContract.claim();
        (
            uint256 totalSharesAfterNextInterval,
            uint256 releasedSharesAfterNextInterval,
            uint256 actualVestedAmountAfterNextInterval,
            uint256 startTimeAfterNextInterval,
            uint256 endTimeAfterNextInterval,
            uint256 cliffTimeAfterNextInterval,
            uint256 vestingIntervalsAfterNextInterval,
            bool isActiveAfterNextInterval,
        ) = vestingContract.vestingInfo(beneficiary);

        assertEq(
            releasedSharesAfterNextInterval,
            expectedSharesNextInterval,
            "Released shares should match the expected shares at the next interval"
        );
        assertEq(actualVestedAmountAfterNextInterval, 0, "Vested amount should remain unchanged after the second claim");
        assertEq(isActiveAfterNextInterval, true, "Vesting should remain active after the second claim");

        // Test at the final interval
        vm.warp(endTime);
        uint256 releasableSharesFinalInterval = vestingContract.getReleasableShares(beneficiary);
        assertEq(
            releasableSharesFinalInterval,
            totalAmount - releasedSharesAfterNextInterval,
            "Incorrect shares releasable at the final interval"
        );

        // Claim at the final interval
        vm.prank(beneficiary);
        vestingContract.claim();
        (
            uint256 totalSharesFinal,
            uint256 releasedSharesFinal,
            uint256 actualVestedAmountFinal,
            uint256 startTimeFinal,
            uint256 endTimeFinal,
            uint256 cliffTimeFinal,
            uint256 vestingIntervalsFinal,
            bool isActiveFinal,
        ) = vestingContract.vestingInfo(beneficiary);

        assertEq(releasedSharesFinal, totalAmount, "All shares should be released at the end of vesting");
    }

    function testNoCliffBehavior() public {
        address beneficiary = address(0x5);

        uint256 totalAmount = 1_000 ether;
        uint256 vestedAmount = 0 ether;
        uint256 cliffDuration = 0; // No cliff
        uint256 intervalDuration = 90 days;
        uint256 totalIntervals = 4;

        // Approve and stake for the beneficiary
        vm.prank(vestingManager);
        ggpTokenMock.approve(address(vestingContract), totalAmount);

        vm.prank(vestingManager);
        vestingContract.stakeOnBehalfOf(
            beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
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
            bool isActive,
        ) = vestingContract.vestingInfo(beneficiary);

        assertEq(cliffTime, startTime, "Cliff time should match start time with no cliff");
        assertEq(isActive, true, "Vesting should be active");

        // Test at the first interval
        vm.warp(startTime + intervalDuration);
        uint256 releasableSharesFirstInterval = vestingContract.getReleasableShares(beneficiary);
        uint256 expectedSharesFirstInterval = (totalAmount * 1) / totalIntervals;
        assertEq(releasableSharesFirstInterval, expectedSharesFirstInterval, "Incorrect shares for the first interval");

        // Claim at the first interval
        vm.prank(beneficiary);
        vestingContract.claim();

        (
            uint256 totalSharesAfterFirstClaim,
            uint256 releasedSharesAfterFirstClaim,
            uint256 actualVestedAmountAfterFirstClaim,
            uint256 startTimeAfterFirstClaim,
            uint256 endTimeAfterFirstClaim,
            uint256 cliffTimeAfterFirstClaim,
            uint256 vestingIntervalsAfterFirstClaim,
            bool isActiveAfterFirstClaim,
        ) = vestingContract.vestingInfo(beneficiary);

        assertEq(
            releasedSharesAfterFirstClaim,
            expectedSharesFirstInterval,
            "Released shares should match expected shares after the first claim"
        );
        assertEq(isActiveAfterFirstClaim, true, "Vesting should remain active after the first claim");

        // Test at the final interval
        vm.warp(endTime);
        uint256 releasableSharesFinalInterval = vestingContract.getReleasableShares(beneficiary);
        assertEq(
            releasableSharesFinalInterval,
            totalAmount - releasedSharesAfterFirstClaim,
            "Incorrect shares for the final interval"
        );

        // Claim all remaining shares
        vm.prank(beneficiary);
        vestingContract.claim();

        (
            uint256 totalSharesFinal,
            uint256 releasedSharesFinal,
            uint256 actualVestedAmountFinal,
            uint256 startTimeFinal,
            uint256 endTimeFinal,
            uint256 cliffTimeFinal,
            uint256 vestingIntervalsFinal,
            bool isActiveFinal,
        ) = vestingContract.vestingInfo(beneficiary);

        assertEq(releasedSharesFinal, totalAmount, "All shares should be released at the end of vesting");
    }

    function testClaimBeforeCliff() public {
        uint256 totalAmount = 1_000 ether;
        uint256 vestedAmount = 0 ether;
        uint256 cliffDuration = 180 days;
        uint256 intervalDuration = 90 days;
        uint256 totalIntervals = 4;

        // Approve and stake
        vm.prank(vestingManager);
        ggpTokenMock.approve(address(vestingContract), totalAmount);

        vm.prank(vestingManager);
        vestingContract.stakeOnBehalfOf(
            beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
        );

        // Warp to a time before the cliff
        vm.warp(block.timestamp + cliffDuration - 1);

        // Attempt to claim before the cliff period
        vm.prank(beneficiary);
        vm.expectRevert("Cliff period not reached");
        vestingContract.claim();
    }

    function testClaimAtCliff() public {
        uint256 totalAmount = 1_000 ether;
        uint256 vestedAmount = 0 ether;
        uint256 cliffDuration = 180 days;
        uint256 intervalDuration = 90 days;
        uint256 totalIntervals = 4;

        // Approve and stake
        vm.prank(vestingManager);
        ggpTokenMock.approve(address(vestingContract), totalAmount);

        vm.prank(vestingManager);
        vestingContract.stakeOnBehalfOf(
            beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
        );

        // Warp to the cliff
        vm.warp(block.timestamp + cliffDuration);

        // Expected shares at the cliff
        uint256 intervalsElapsed = cliffDuration / intervalDuration;
        uint256 expectedSharesAtCliff = (totalAmount * intervalsElapsed) / totalIntervals;

        // Claim at the cliff
        vm.prank(beneficiary);
        vestingContract.claim();

        // Validate the vesting state after the claim
        (
            uint256 totalShares,
            uint256 releasedShares,
            uint256 actualVestedAmount,
            uint256 startTime,
            uint256 endTime,
            uint256 cliffTime,
            uint256 vestingIntervals,
            bool isActive,
        ) = vestingContract.vestingInfo(beneficiary);

        assertEq(releasedShares, expectedSharesAtCliff, "Incorrect released shares after claim at the cliff");
        assertEq(actualVestedAmount, 0, "Incorrect vested amount after claim at the cliff");
        assertEq(isActive, true, "Vesting should remain active after claiming at the cliff");
    }

    function testClaimAtInterval() public {
        uint256 totalAmount = 1_000 ether;
        uint256 vestedAmount = 0 ether;
        uint256 cliffDuration = 0; // No cliff
        uint256 intervalDuration = 90 days;
        uint256 totalIntervals = 4;

        // Approve and stake
        vm.prank(vestingManager);
        ggpTokenMock.approve(address(vestingContract), totalAmount);

        vm.prank(vestingManager);
        vestingContract.stakeOnBehalfOf(
            beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
        );

        // Warp to the second interval
        vm.warp(block.timestamp + intervalDuration * 2);

        // Expected shares at the second interval
        uint256 expectedShares = (totalAmount * 2) / totalIntervals;

        // Claim
        vm.prank(beneficiary);
        vestingContract.claim();

        // Validate the vesting state after the claim
        (
            uint256 totalShares,
            uint256 releasedShares,
            uint256 actualVestedAmount,
            uint256 startTime,
            uint256 endTime,
            uint256 cliffTime,
            uint256 vestingIntervals,
            bool isActive,
        ) = vestingContract.vestingInfo(beneficiary);

        assertEq(releasedShares, expectedShares, "Incorrect released shares after claim at the second interval");
        assertEq(actualVestedAmount, 0, "Incorrect vested amount after claim at the second interval");
        assertEq(isActive, true, "Vesting should remain active after claiming at the second interval");
    }

    function testFullClaimAtEnd() public {
        uint256 totalAmount = 1_000 ether;
        uint256 vestedAmount = 0 ether;
        uint256 cliffDuration = 0; // No cliff
        uint256 intervalDuration = 90 days;
        uint256 totalIntervals = 4;

        // Approve and stake
        vm.prank(vestingManager);
        ggpTokenMock.approve(address(vestingContract), totalAmount);

        vm.prank(vestingManager);
        vestingContract.stakeOnBehalfOf(
            beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
        );

        // Warp to the end of the vesting period
        vm.warp(block.timestamp + intervalDuration * totalIntervals);

        // Claim all remaining shares
        vm.prank(beneficiary);
        vestingContract.claim();

        // Validate the vesting state after the claim
        (
            uint256 totalShares,
            uint256 releasedShares,
            uint256 actualVestedAmount,
            uint256 startTime,
            uint256 endTime,
            uint256 cliffTime,
            uint256 vestingIntervals,
            bool isActive,
        ) = vestingContract.vestingInfo(beneficiary);
    }

    function testUnauthorizedClaim() public {
        uint256 totalAmount = 1_000 ether;
        uint256 vestedAmount = 0 ether;
        uint256 cliffDuration = 0; // No cliff
        uint256 intervalDuration = 90 days;
        uint256 totalIntervals = 4;

        // Approve and stake
        vm.prank(vestingManager);
        ggpTokenMock.approve(address(vestingContract), totalAmount);

        vm.prank(vestingManager);
        vestingContract.stakeOnBehalfOf(
            beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
        );

        // Warp to an interval
        vm.warp(block.timestamp + intervalDuration);

        // Attempt to claim from an unauthorized address
        vm.prank(address(0x6)); // Not the beneficiary
        vm.expectRevert("No active vesting");
        vestingContract.claim();
    }

    function testPartialClaimAcrossIntervals() public {
        uint256 totalAmount = 1_000 ether;
        uint256 vestedAmount = 0 ether;
        uint256 cliffDuration = 0; // No cliff
        uint256 intervalDuration = 90 days;
        uint256 totalIntervals = 4;

        // Approve and stake
        vm.prank(vestingManager);
        ggpTokenMock.approve(address(vestingContract), totalAmount);

        vm.prank(vestingManager);
        vestingContract.stakeOnBehalfOf(
            beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
        );

        // Warp to the first interval and claim
        vm.warp(block.timestamp + intervalDuration);
        vm.prank(beneficiary);
        vestingContract.claim();

        // Warp to the second interval and claim again
        vm.warp(block.timestamp + intervalDuration);
        vm.prank(beneficiary);
        vestingContract.claim();

        // Validate the state after two claims
        uint256 expectedSharesAfterTwoIntervals = (totalAmount * 2) / totalIntervals;
        (
            uint256 totalShares,
            uint256 releasedShares,
            uint256 actualVestedAmount,
            uint256 startTime,
            uint256 endTime,
            uint256 cliffTime,
            uint256 vestingIntervals,
            bool isActive,
        ) = vestingContract.vestingInfo(beneficiary);

        assertEq(releasedShares, expectedSharesAfterTwoIntervals, "Incorrect released shares after two claims");
        assertEq(isActive, true, "Vesting should remain active after two claims");
    }

    function testPreventOverclaimAfterVestingEnds() public {
        uint256 totalAmount = 1_000 ether;
        uint256 vestedAmount = 0 ether;
        uint256 cliffDuration = 0; // No cliff
        uint256 intervalDuration = 90 days;
        uint256 totalIntervals = 4;

        // Approve and stake
        vm.prank(vestingManager);
        ggpTokenMock.approve(address(vestingContract), totalAmount);

        vm.prank(vestingManager);
        vestingContract.stakeOnBehalfOf(
            beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
        );

        // Warp to the end of the vesting period
        vm.warp(block.timestamp + intervalDuration * totalIntervals);

        // Claim all remaining shares
        vm.prank(beneficiary);
        vestingContract.claim();

        // Validate the vesting state after the full claim
        (
            uint256 totalShares,
            uint256 releasedShares,
            uint256 actualVestedAmount,
            uint256 startTime,
            uint256 endTime,
            uint256 cliffTime,
            uint256 vestingIntervals,
            bool isActive,
        ) = vestingContract.vestingInfo(beneficiary);

        assertEq(releasedShares, totalAmount, "All shares should be released after the final claim");

        // Attempt to claim again after all shares have been released
        vm.prank(beneficiary);
        vm.expectRevert();
        vestingContract.claim();

        // Validate that no additional shares were released
        (totalShares, releasedShares, actualVestedAmount, startTime, endTime, cliffTime, vestingIntervals, isActive,) =
            vestingContract.vestingInfo(beneficiary);

        assertEq(releasedShares, totalAmount, "Released shares should not exceed the total amount allocated");
    }

    function testAccessControlForRoles() public {
        bytes32 vestingManagerRole = vestingContract.VESTING_MANAGER_ROLE();
        bytes32 defaultAdminRole = vestingContract.DEFAULT_ADMIN_ROLE();

        // Ensure owner has admin role
        assertTrue(vestingContract.hasRole(defaultAdminRole, owner), "Owner should have admin role");

        // Ensure vestingManager has the vesting manager role
        assertTrue(
            vestingContract.hasRole(vestingManagerRole, vestingManager),
            "VestingManager should have vesting manager role"
        );

        // Unauthorized address trying to call `stakeOnBehalfOf`
        vm.prank(address(0x6)); // Unauthorized address
        vm.expectRevert();
        vestingContract.stakeOnBehalfOf(beneficiary, 1_000 ether, 0, 180 days, 90 days, 4);

        // Unauthorized address trying to call `cancelVesting`
        vm.prank(address(0x6)); // Unauthorized address
        vm.expectRevert();
        vestingContract.cancelVesting(beneficiary);

        // Grant vesting manager role from admin
        vm.prank(owner);
        vestingContract.grantRole(vestingManagerRole, address(0x7));
        assertTrue(
            vestingContract.hasRole(vestingManagerRole, address(0x7)), "New address should have vesting manager role"
        );

        // Revoke vesting manager role from admin
        vm.prank(owner);
        vestingContract.revokeRole(vestingManagerRole, vestingManager);
        assertFalse(
            vestingContract.hasRole(vestingManagerRole, vestingManager), "VestingManager role should be revoked"
        );

        // Unauthorized address trying to grant roles
        vm.prank(address(0x6)); // Unauthorized address
        vm.expectRevert();
        vestingContract.grantRole(vestingManagerRole, address(0x8));

        // Unauthorized address trying to revoke roles
        vm.prank(address(0x6)); // Unauthorized address
        vm.expectRevert();
        vestingContract.revokeRole(vestingManagerRole, address(0x7));

        // Admin renouncing their own role
        vm.prank(owner);
        vestingContract.renounceRole(defaultAdminRole, owner);
        assertFalse(vestingContract.hasRole(defaultAdminRole, owner), "Owner should have renounced admin role");
    }

    function testUpgrade() public {
        // Get the implementation address before the upgrade
        address implAddressV1 = Upgrades.getImplementationAddress(address(vestingContract));

        // Ensure the original contract does not have the new method
        vm.expectRevert();
        VestingContractV2(address(vestingContract)).newMethod();

        // Deploy the new implementation and upgrade the proxy
        Upgrades.upgradeProxy(
            address(vestingContract), "VestingContractV2.sol", abi.encodeCall(VestingContractV2.newMethod, ())
        );

        // Get the implementation address after the upgrade
        address implAddressV2 = Upgrades.getImplementationAddress(address(vestingContract));

        // Assert that the implementation address has changed
        assertFalse(implAddressV1 == implAddressV2, "Implementation address should have changed after upgrade");

        // Interact with the upgraded contract
        VestingContractV2 upgradedContract = VestingContractV2(address(vestingContract));

        // Verify the new method works
        string memory result = upgradedContract.newMethod();
        assertEq(result, "meow", "The new method should return 'meow'");
    }
}
