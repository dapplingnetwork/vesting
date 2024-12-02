// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

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
        uint256 cliffDuration,
        uint256 intervalDuration,
        uint256 totalIntervals
    ) external onlyRole(VESTING_MANAGER_ROLE) {
        require(totalAmount > 0, "Amount must be greater than zero");
        require(totalIntervals > 0, "Intervals must be greater than zero");

        Vesting storage vesting = vestingInfo[beneficiary];
        require(!vesting.isActive, "Existing vesting already active");

        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + (intervalDuration * totalIntervals);
        uint256 cliffTime = startTime + cliffDuration;

        // Deposit GGP into Seafi Vault
        token.approve(address(seafiVault), totalAmount);
        uint256 shares = seafiVault.deposit(totalAmount, address(this));
        require(shares > 0, "Vault deposit failed");

        vesting.totalShares = shares;
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
        require(releasableShares > 0, "No shares available for release");

        vesting.releasedShares += releasableShares;

        // Redeem xGGP shares for GGP
        uint256 redeemedAssets = seafiVault.redeem(releasableShares, msg.sender, address(this));
        require(redeemedAssets > 0, "Vault redemption failed");

        emit Claimed(msg.sender, redeemedAssets);
    }

    function cancelVesting(address beneficiary) external onlyRole(VESTING_MANAGER_ROLE) {
        Vesting storage vesting = vestingInfo[beneficiary];
        require(vesting.isActive, "Vesting not active");

        uint256 remainingShares = vesting.totalShares - vesting.releasedShares;
        require(remainingShares > 0, "No remaining shares to withdraw");

        vesting.isActive = false;

        // Redeem remaining xGGP shares for GGP
        uint256 refundedAssets = seafiVault.redeem(remainingShares, msg.sender, address(this));
        require(refundedAssets > 0, "Vault redemption failed");

        emit VestingCancelled(beneficiary, remainingShares, refundedAssets);
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
