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

    function test_CanClaimEvenWhenVestingEndTimeExceeds() public {
        _vest();
        (,,,, uint256 endTimeAfterClaim,,,) = vestingContract.vestingInfo(beneficiary);
        vm.warp(block.timestamp + endTimeAfterClaim + 1000);

        vm.prank(beneficiary);
        vestingContract.claim();
    }

    function test_RevertsIfSeafiVaultReverts() public {
        _vest();
        (,,,,, uint256 cliffTime,,) = vestingContract.vestingInfo(beneficiary);
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

    function test_DisproportionalReleasableShares() public {
        _vest();
        (
            /* uint256 totalSharesAfterClaim */
            ,
            /*  uint256 releasedSharesAfterClaim */
            ,
            /* uint256 actualVestedAmountAfterClaim */
            ,
            /* uint256 startTimeAfterClaim */
            ,
            uint256 endTimeAfterClaim,
            /* uint256 cliffTimeAfterClaim */
            ,
            /* uint256 vestingIntervalsAfterClaim */
            ,
            /* bool isActiveAfterClaim */
        ) = vestingContract.vestingInfo(beneficiary);

        vm.warp(block.timestamp + endTimeAfterClaim);
        uint256 maxReleasableShares = vestingContract.getReleasableShares(beneficiary);
        vm.warp(block.timestamp + 2 * 365 days);
        assertLt(endTimeAfterClaim, block.timestamp);

        uint256 releasableShares = vestingContract.getReleasableShares(beneficiary);
        console.log("maxReleasableShares:", maxReleasableShares, "releasableShares", releasableShares);
        assert(maxReleasableShares < releasableShares);
    }

    function _vest() internal {
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
    }
}