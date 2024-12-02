// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "forge-std/console.sol";

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IGGPVault {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
}

contract VestingContract is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    bytes32 public constant VESTING_MANAGER_ROLE = keccak256("VESTING_MANAGER_ROLE");

    struct Vesting {
        uint256 totalShares; // xGGP shares deposited in the vault
        uint256 releasedShares; // xGGP shares redeemed so far
        uint256 vestedAmount; // Amount of GGP already vested
        uint256 startTime; // Vesting start time
        uint256 endTime; // Vesting end time
        uint256 cliffTime; // Cliff period
        uint256 vestingIntervals; // Number of intervals (e.g., 16 for 4 years quarterly)
        bool isActive; // Indicates if the vesting is active
    }

    mapping(address => Vesting) public vestingInfo; // beneficiary -> vesting details

    IGGPVault public seafiVault; // The vault to deposit/redeem xGGP
    IERC20 public token; // The ERC20 token being deposited

    event StakedOnBehalf(address indexed beneficiary, uint256 totalShares, uint256 startTime, uint256 endTime);
    event Claimed(address indexed beneficiary, uint256 assets);
    event VestingCancelled(address indexed beneficiary, uint256 remainingShares, uint256 refundedAssets);
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

        Vesting storage vesting = vestingInfo[beneficiary];
        require(!vesting.isActive, "Existing vesting already active");

        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + (intervalDuration * totalIntervals);
        uint256 cliffTime = startTime + cliffDuration;

        token.transferFrom(msg.sender, address(this), totalAmount);

        token.approve(address(seafiVault), totalAmount - vestedAmount);
        uint256 shares = seafiVault.deposit(totalAmount - vestedAmount, address(this));

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

    function claim() external {
        Vesting storage vesting = vestingInfo[msg.sender];
        require(vesting.isActive, "No active vesting");
        require(block.timestamp >= vesting.cliffTime, "Cliff period not reached");

        uint256 releasableShares = getReleasableShares(msg.sender);
        uint256 releasableAssets;

        // Include already vested amount if it has not been claimed
        if (vesting.vestedAmount > 0) {
            releasableAssets = vesting.vestedAmount;
            vesting.vestedAmount = 0; // Mark as claimed
        }

        if (releasableShares > 0) {
            releasableAssets += seafiVault.redeem(releasableShares, msg.sender, address(this));
            vesting.releasedShares += releasableShares;
        }

        require(releasableAssets > 0, "No assets available for release");

        emit Claimed(msg.sender, releasableAssets);
    }

    function cancelVesting(address beneficiary) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Vesting storage vesting = vestingInfo[beneficiary];
        require(vesting.isActive, "Vesting not active");

        // Calculate remaining shares and vested GGP
        uint256 remainingShares = vesting.totalShares - vesting.releasedShares;
        uint256 vestedAmount = vesting.vestedAmount;

        require(remainingShares > 0 || vestedAmount > 0, "No assets to withdraw");

        // Mark vesting as inactive
        vesting.isActive = false;

        uint256 refundedAssets = 0;

        // Redeem remaining xGGP shares from the vault for GGP
        if (remainingShares > 0) {
            refundedAssets = seafiVault.redeem(remainingShares, msg.sender, address(this));
            require(refundedAssets > 0, "Vault redemption failed");
        }

        // Transfer vested GGP from the contract to the admin
        if (vestedAmount > 0) {
            require(token.transfer(msg.sender, vestedAmount), "Vested GGP transfer failed");
        }

        emit VestingCancelled(beneficiary, remainingShares, refundedAssets + vestedAmount);
    }

    function getReleasableShares(address beneficiary) public view returns (uint256) {
        Vesting storage vesting = vestingInfo[beneficiary];
        if (block.timestamp < vesting.cliffTime || !vesting.isActive) {
            return 0;
        }

        uint256 totalTime = vesting.endTime - vesting.startTime;
        uint256 timeElapsed = block.timestamp - vesting.startTime;
        uint256 totalIntervals = vesting.vestingIntervals;

        uint256 totalUnlockedShares =
            (vesting.totalShares * (timeElapsed * totalIntervals / totalTime)) / totalIntervals;
        return totalUnlockedShares - vesting.releasedShares;
    }

    /// @notice Required override for UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
