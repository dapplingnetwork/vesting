// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {VestingContract} from "../contracts/VestingContract.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {GGPVaultMock} from "./mocks/GGPVaultMock.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract AuditVestingContractTest is Test {
    VestingContract public vestingContract;
    GGPVaultMock public ggpVaultMock;
    ERC20Mock public ggpTokenMock;
    address public owner;
    address public vestingManager;
    address public beneficiary;
    VestingContract implementation;

    function setUp() public {
        // Initialize mock contracts
        owner = address(this);
        vestingManager = address(0x1);
        beneficiary = address(0x2);

        ggpTokenMock = new ERC20Mock();
        ggpVaultMock = new GGPVaultMock(ggpTokenMock);

        // Deploy VestingContract as a UUPS proxy
        implementation = new VestingContract();

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

    function test_CanClaimEvenWhenVestingEndTimeExceeds() public {
        _vest(beneficiary, 1_000 ether);
        (,,,, uint256 endTimeAfterClaim,,,,) = vestingContract.vestingInfo(beneficiary);
        vm.warp(block.timestamp + endTimeAfterClaim + 1000);

        vm.prank(beneficiary);
        vestingContract.claim();
    }

    function test_RevertsIfSeafiVaultReverts() public {
        _vest(beneficiary, 1_000 ether);
        (,,,,, uint256 cliffTime,,,) = vestingContract.vestingInfo(beneficiary);
        vm.warp(block.timestamp + cliffTime);

        uint256 releasableShares = vestingContract.getReleasableShares(beneficiary);

        console.log(releasableShares, beneficiary, address(vestingContract));

        vm.mockCallRevert(
            address(ggpVaultMock),
            abi.encodeWithSelector(
                ggpVaultMock.redeem.selector, releasableShares, beneficiary, address(vestingContract)
            ),
            abi.encodeWithSignature("Error(string)", "Forced revert")
        );
        vm.prank(beneficiary);
        vm.expectRevert("Forced revert");
        vestingContract.claim();
    }

    function test_CanClaimMoreThanExpected() public {
        _vest(beneficiary, 1_000 ether);
        _vest(makeAddr("beneficiary2"), 2_000 ether);
        _vest(makeAddr("beneficiary3"), 2_000 ether);
        _vest(makeAddr("beneficiary4"), 2_000 ether);

        (,,,, uint256 endTimeAfterClaim,,,,) = vestingContract.vestingInfo(beneficiary);

        vm.warp(block.timestamp + endTimeAfterClaim);
        uint256 maxReleasableShares = vestingContract.getReleasableShares(beneficiary);
        vm.warp(block.timestamp + 365 days);
        assertLt(endTimeAfterClaim, block.timestamp);

        uint256 releasableShares = vestingContract.getReleasableShares(beneficiary);

        assert(maxReleasableShares == releasableShares);
        vm.prank(beneficiary);
        vestingContract.claim();
    }

    function test_GetsMaxYieldAfterEndTime() public {
        _vest(beneficiary, 1_000 ether);
        (,,,, uint256 endTimeAfterClaim,,,,) = vestingContract.vestingInfo(beneficiary);

        vm.warp(block.timestamp + endTimeAfterClaim);
        uint256 maxReleasableShares = vestingContract.getReleasableShares(beneficiary);

        vm.warp(block.timestamp + 365 days);

        uint256 releasableSharesAfter = vestingContract.getReleasableShares(beneficiary);

        assertLe(maxReleasableShares, releasableSharesAfter, "Unexpected Releasable Shares");
    }

    function test_ClaimsMaxYieldAfterEndTime() public {
        test_GetsMaxYieldAfterEndTime();
        uint256 startingGGPBalance = ggpTokenMock.balanceOf(beneficiary);

        vm.prank(beneficiary);
        vestingContract.claim();

        uint256 endingGGPBalance = ggpTokenMock.balanceOf(beneficiary);
        assertGe(endingGGPBalance, startingGGPBalance);
    }

    function test_CannotCancelVestingOnceClaimed() public {
        _vest(beneficiary, 1_000 ether);

        vm.warp(block.timestamp + 365 days);

        vm.prank(beneficiary);
        vestingContract.claim();

        vm.expectRevert(bytes("No assets to withdraw"));
        vestingContract.cancelVesting(beneficiary);
    }

    function testFuzz_StakeOnBehalfOf(
        address _beneficiary,
        uint256 totalAmount,
        uint256 vestedAmount,
        uint256 cliffDuration,
        uint256 intervalDuration,
        uint256 totalIntervals
    ) public {
        // vm.skip(true);
        vm.assume(_beneficiary != address(0));
        cliffDuration = bound(cliffDuration, 0, 365 days);
        intervalDuration = bound(intervalDuration, 1, 365 days);
        totalIntervals = bound(totalIntervals, 0, 100);
        vestedAmount = bound(vestedAmount, 0, 1_000_000 ether);
        totalAmount = bound(totalAmount, 0, 1_000_000 ether);

        vm.startPrank(vestingManager);
        ggpTokenMock.approve(address(vestingContract), totalAmount);

        // Test vestedAmount <= totalAmount
        if (totalAmount == 0 || totalIntervals == 0) {
            vm.expectRevert();
            vestingContract.stakeOnBehalfOf(
                _beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
            );
            return;
        }

        if (vestedAmount > totalAmount) {
            vm.expectRevert("Vested amount cannot exceed total amount");
            vestingContract.stakeOnBehalfOf(
                _beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
            );
            return;
        }

        // Test cliffDuration <= intervalDuration * totalIntervals
        if (cliffDuration > intervalDuration * totalIntervals) {
            vm.expectRevert("Cliff duration exceeds total vesting period");
            vestingContract.stakeOnBehalfOf(
                _beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
            );
            return;
        }

        // Test cliffDuration > 0 implies vestedAmount == 0
        if (cliffDuration > 0 && vestedAmount > 0) {
            vm.expectRevert("Vested amount must be zero if cliff duration is specified");
            vestingContract.stakeOnBehalfOf(
                _beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
            );
            return;
        }

        // Test cliffDuration == 0 or cliffDuration >= intervalDuration
        if (cliffDuration > 0 && cliffDuration < intervalDuration) {
            vm.expectRevert("Cliff duration must be >= interval duration");
            vestingContract.stakeOnBehalfOf(
                _beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
            );
            return;
        }
        // If all assumptions pass, call the function
        vestingContract.stakeOnBehalfOf(
            _beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
        );
        vm.stopPrank();

        // Verify outputs (can vary based on implementation)
    }

    function _vest(address _beneficiary, uint256 totalAmount) internal {
        // uint256 totalAmount = 1_000 ether;
        uint256 vestedAmount = 0 ether;
        uint256 cliffDuration = 60 days;
        uint256 intervalDuration = 30 days;
        uint256 totalIntervals = 4;

        // Approve and stake
        vm.prank(vestingManager);
        ggpTokenMock.approve(address(vestingContract), totalAmount);

        vm.prank(vestingManager);
        vestingContract.stakeOnBehalfOf(
            _beneficiary, totalAmount, vestedAmount, cliffDuration, intervalDuration, totalIntervals
        );
    }

    function test_ClaimsWithNonZeroVestedAmount() public {
        uint256 vestedAmount = 1 ether;
        uint256 cliffDuration = 0;
        uint256 intervalDuration = 30 days;
        uint256 totalIntervals = 4;

        // Approve and stake
        vm.prank(vestingManager);
        ggpTokenMock.approve(address(vestingContract), 1_000 ether);

        vm.prank(vestingManager);
        vestingContract.stakeOnBehalfOf(
            beneficiary, 1_000 ether, vestedAmount, cliffDuration, intervalDuration, totalIntervals
        );

        vm.prank(beneficiary);
        vestingContract.claim();
    }

    function test_CancelsWithNonZeroVestedAmount() public {
        uint256 vestedAmount = 1 ether;
        uint256 cliffDuration = 0;
        uint256 intervalDuration = 30 days;
        uint256 totalIntervals = 4;

        // Approve and stake
        vm.prank(vestingManager);
        ggpTokenMock.approve(address(vestingContract), 1_000 ether);
        deal(address(ggpTokenMock), address(vestingContract), vestedAmount);
        vm.prank(vestingManager);
        vestingContract.stakeOnBehalfOf(
            beneficiary, 1_000 ether, vestedAmount, cliffDuration, intervalDuration, totalIntervals
        );

        vestingContract.cancelVesting(beneficiary);
    }

    function test_RevertsCancelWithNonZeroVestedAmountAndNotEnoughGGPBalance() public {
        uint256 vestedAmount = 1 ether;
        uint256 cliffDuration = 0;
        uint256 intervalDuration = 30 days;
        uint256 totalIntervals = 4;

        // Approve and stake
        vm.prank(vestingManager);
        ggpTokenMock.approve(address(vestingContract), 1_000 ether);

        vm.prank(vestingManager);
        vestingContract.stakeOnBehalfOf(
            beneficiary, 1_000 ether, vestedAmount, cliffDuration, intervalDuration, totalIntervals
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("ERC20InsufficientBalance(address,uint256,uint256)")),
                address(vestingContract),
                ggpTokenMock.balanceOf(address(vestingContract)),
                vestedAmount
            )
        );
        vestingContract.cancelVesting(beneficiary);
    }

    function test_CannotCancelInactiveVestings() public {
        vm.expectRevert("Vesting not active");
        vestingContract.cancelVesting(makeAddr("inactiveAccount"));
    }
}
