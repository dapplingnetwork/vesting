// SPDX-License-Identifier: MIT
//@audit use a specific solidity version

pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IGGPVault {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
}

contract VestingContract is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    bytes32 public constant VESTING_MANAGER_ROLE = keccak256("VESTING_MANAGER_ROLE");

    //@q saves single or all time vestings?: Single, once

    struct Vesting {
        uint256 totalShares; // xGGP shares deposited in the vault
        uint256 releasedShares; // xGGP shares redeemed so far
        uint256 vestedAmount; // Amount of GGP already vested
        uint256 startTime; // Vesting start time
        uint256 endTime; // Vesting end time
        uint256 cliffTime; // Cliff period
        uint256 vestingIntervals; // Number of intervals (e.g., 16 for 4 years quarterly)
        bool isActive; // Indicates if the vesting is active
        bool vestAmountClaimed; // Indicates if the vestedAmount was claimed
    }

    mapping(address => Vesting) public vestingInfo; // beneficiary -> vesting details
    uint256 withdrawShares;

    IGGPVault public seafiVault; // The vault to deposit/redeem xGGP
    IERC20 public token; // The ERC20 token being deposited

    event StakedOnBehalf(address indexed beneficiary, uint256 totalShares, uint256 startTime, uint256 endTime);
    event Claimed(address indexed beneficiary, uint256 assets);
    event VestingCancelled(address indexed beneficiary, uint256 remainingShares, uint256 refundedShares);
    event VestingCancelled2(address indexed beneficiary, uint256 remainingShares);

    event Withdraw(uint256 assetsWithdrawn);
    /// @custom:oz-upgrades-unsafe-allow constructor

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializer function (replaces constructor for upgradeable contracts)
    /// @param admin The admin address for the contract.
    /// @param vault The address of the vault (GGPVault).
    /// @param _token The ERC20 token used for deposits.
    function initialize(address admin, address vault, address _token) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin); // Admin role manages all other roles
        _grantRole(VESTING_MANAGER_ROLE, admin); // Grant the deployer the vesting manager role

        seafiVault = IGGPVault(vault);
        token = IERC20(_token);
    }

    function stakeOnBehalfOf(
        address beneficiary,
        uint256 totalAmount, // GGP to be deposited
        uint256 vestedAmount, // GGP already vested
        uint256 cliffDuration,
        uint256 intervalDuration,
        uint256 totalIntervals
    ) external onlyRole(VESTING_MANAGER_ROLE) {
        require(totalAmount > 0, "Amount must be greater than zero");
        require(totalIntervals > 0, "Intervals must be greater than zero");
        require(vestedAmount <= totalAmount, "Vested amount cannot exceed total amount");
        require(cliffDuration <= intervalDuration * totalIntervals, "Cliff duration exceeds total vesting period");

        if (cliffDuration > 0) {
            require(vestedAmount == 0, "Vested amount must be zero if cliff duration is specified");
        }

        require(cliffDuration == 0 || cliffDuration >= intervalDuration, "Cliff duration must be >= interval duration");

        Vesting storage vesting = vestingInfo[beneficiary];
        require(!vesting.isActive, "Existing vesting already active");

        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + (intervalDuration * totalIntervals);
        uint256 cliffTime = startTime + cliffDuration;

        token.transferFrom(msg.sender, address(this), totalAmount);
        token.approve(address(seafiVault), totalAmount);

        uint256 shares = seafiVault.deposit(totalAmount, address(this));

        require(shares > 0, "Vault deposit failed");
        vesting.totalShares = shares;
        vesting.vestedAmount = vestedAmount;
        vesting.startTime = startTime;
        vesting.endTime = endTime;
        vesting.cliffTime = cliffTime;
        vesting.vestingIntervals = totalIntervals;
        vesting.isActive = true;

        emit StakedOnBehalf(beneficiary, shares, startTime, endTime);
    }
    // Other contract functions remain unchanged...

    function claim() external {
        Vesting storage vesting = vestingInfo[msg.sender];
        require(vesting.isActive, "No active vesting");
        require(block.timestamp >= vesting.cliffTime, "Cliff period not reached");

        uint256 releasableShares = getReleasableShares(msg.sender);
        uint256 releasableAssets;

        if (vesting.vestedAmount > 0 && !vesting.vestAmountClaimed) {
            uint256 vestedShares = seafiVault.convertToShares(vesting.vestedAmount);
            vesting.vestAmountClaimed = true; // Mark as claimed
            releasableAssets = seafiVault.redeem(vestedShares, msg.sender, address(this));
        }

        if (releasableShares > 0) {
            releasableAssets += seafiVault.redeem(releasableShares, msg.sender, address(this));
            vesting.releasedShares += releasableShares;
        }

        require(releasableAssets > 0, "No assets available for release");

        emit Claimed(msg.sender, releasableAssets);
    }

    // withdraws cumulated shares from canceled Vesting ones.
    function withdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 shares = withdrawShares;
        require(shares > 0, "No shares available to withdraw");

        uint256 assetsWithdrawn = seafiVault.redeem(shares, msg.sender, address(this));
        require(assetsWithdrawn > 0, "Vault redemption failed");

        withdrawShares -= shares;

        emit Withdraw(assetsWithdrawn);
    }

    // Schedules the admin's shares to refund
    function cancelVesting(address beneficiary) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Vesting storage vesting = vestingInfo[beneficiary];
        require(vesting.isActive, "Vesting not active");
        vesting.isActive = false;

        uint256 remainingShares = vesting.totalShares - vesting.releasedShares;
        //acrued yield at the time on cancel since the last claim
        uint256 yield = getReleasableShares(beneficiary);
        uint256 refundShares = vesting.totalShares + yield;
        if (vesting.vestAmountClaimed) {
            refundShares -= seafiVault.convertToShares(vesting.vestedAmount);
        }

        withdrawShares += refundShares;
        emit VestingCancelled(beneficiary, remainingShares, refundShares);
    }

    function getReleasableShares(address beneficiary) public view returns (uint256) {
        Vesting storage vesting = vestingInfo[beneficiary];
        if (block.timestamp < vesting.cliffTime || !vesting.isActive) {
            return 0;
        }

        uint256 totalTime = vesting.endTime - vesting.startTime;
        uint256 timeElapsed = block.timestamp > vesting.endTime ? totalTime : block.timestamp - vesting.startTime;
        uint256 totalUnlockedShares = (vesting.totalShares * timeElapsed / totalTime);
        return totalUnlockedShares - vesting.releasedShares;
    }

    /// @notice Required override for UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
