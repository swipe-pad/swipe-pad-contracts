// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title BetaDonationPool
 * @notice Secure treasury pool for beta donations - NO off-chain private keys needed
 * @dev Users receive on-chain credits, then execute donations themselves.
 *      The contract transfers tokens from its own balance to recipients.
 *      
 *      Security Model:
 *      - Treasury deposits tokens to this contract
 *      - Admin (multisig) grants credits to approved beta users
 *      - Users call donate() which transfers from pool, not their wallet
 *      - No private keys held by any off-chain service
 */
contract BetaDonationPool is Ownable, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Credit balance per user (in smallest token units)
    mapping(address => uint256) public credits;

    /// @notice Supported donation token (cUSD on Celo, USDC on Base)
    IERC20 public immutable token;

    /// @notice Maximum credits per user
    uint256 public maxCreditsPerUser;

    /// @notice Minimum donation amount per recipient
    uint256 public minDonationAmount;

    /// @notice Maximum recipients per batch
    uint256 public constant MAX_BATCH_SIZE = 50;

    // Events
    event CreditsGranted(address indexed user, uint256 amount);
    event CreditsRevoked(address indexed user, uint256 amount);
    event Donation(
        address indexed donor,
        address indexed recipient,
        uint256 amount
    );
    event BatchDonation(
        address indexed donor,
        uint256 totalAmount,
        uint256 recipientCount
    );
    event PoolFunded(address indexed funder, uint256 amount);
    event PoolDrained(address indexed to, uint256 amount);

    // Errors
    error InsufficientCredits(uint256 requested, uint256 available);
    error InsufficientPoolBalance(uint256 requested, uint256 available);
    error ArrayLengthMismatch();
    error BatchTooLarge(uint256 size, uint256 max);
    error AmountBelowMinimum(uint256 amount, uint256 minimum);
    error ZeroAddress();
    error ZeroAmount();
    error ExceedsMaxCredits(uint256 total, uint256 max);

    constructor(
        address _token,
        address _owner,
        uint256 _maxCreditsPerUser,
        uint256 _minDonationAmount
    ) Ownable(_owner) {
        if (_token == address(0)) revert ZeroAddress();
        token = IERC20(_token);
        maxCreditsPerUser = _maxCreditsPerUser;
        minDonationAmount = _minDonationAmount;
    }

    // ============================================
    // User Functions
    // ============================================

    /**
     * @notice Donate to a single recipient using your credits
     * @param recipient Address to receive the donation
     * @param amount Amount of tokens to donate
     */
    function donate(address recipient, uint256 amount) external whenNotPaused {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (amount < minDonationAmount) {
            revert AmountBelowMinimum(amount, minDonationAmount);
        }
        if (credits[msg.sender] < amount) {
            revert InsufficientCredits(amount, credits[msg.sender]);
        }

        uint256 poolBalance = token.balanceOf(address(this));
        if (poolBalance < amount) {
            revert InsufficientPoolBalance(amount, poolBalance);
        }

        credits[msg.sender] -= amount;
        token.safeTransfer(recipient, amount);

        emit Donation(msg.sender, recipient, amount);
    }

    /**
     * @notice Donate to multiple recipients in a single transaction
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts for each recipient
     */
    function batchDonate(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external whenNotPaused {
        uint256 length = recipients.length;

        if (length != amounts.length) revert ArrayLengthMismatch();
        if (length > MAX_BATCH_SIZE) revert BatchTooLarge(length, MAX_BATCH_SIZE);

        uint256 totalAmount;
        for (uint256 i; i < length; ) {
            if (recipients[i] == address(0)) revert ZeroAddress();
            if (amounts[i] == 0) revert ZeroAmount();
            if (amounts[i] < minDonationAmount) {
                revert AmountBelowMinimum(amounts[i], minDonationAmount);
            }
            totalAmount += amounts[i];
            unchecked { ++i; }
        }

        if (credits[msg.sender] < totalAmount) {
            revert InsufficientCredits(totalAmount, credits[msg.sender]);
        }

        uint256 poolBalance = token.balanceOf(address(this));
        if (poolBalance < totalAmount) {
            revert InsufficientPoolBalance(totalAmount, poolBalance);
        }

        credits[msg.sender] -= totalAmount;

        for (uint256 i; i < length; ) {
            token.safeTransfer(recipients[i], amounts[i]);
            emit Donation(msg.sender, recipients[i], amounts[i]);
            unchecked { ++i; }
        }

        emit BatchDonation(msg.sender, totalAmount, length);
    }

    /**
     * @notice Check remaining credits for a user
     */
    function getCredits(address user) external view returns (uint256) {
        return credits[user];
    }

    // ============================================
    // Admin Functions (Multisig)
    // ============================================

    /**
     * @notice Grant credits to a beta user
     * @param user Address to receive credits
     * @param amount Amount of credits to grant
     */
    function grantCredits(address user, uint256 amount) external onlyOwner {
        if (user == address(0)) revert ZeroAddress();
        
        uint256 newTotal = credits[user] + amount;
        if (newTotal > maxCreditsPerUser) {
            revert ExceedsMaxCredits(newTotal, maxCreditsPerUser);
        }

        credits[user] = newTotal;
        emit CreditsGranted(user, amount);
    }

    /**
     * @notice Grant credits to multiple users at once
     * @param users Array of user addresses
     * @param amounts Array of credit amounts
     */
    function batchGrantCredits(
        address[] calldata users,
        uint256[] calldata amounts
    ) external onlyOwner {
        if (users.length != amounts.length) revert ArrayLengthMismatch();

        for (uint256 i; i < users.length; ) {
            if (users[i] == address(0)) revert ZeroAddress();
            
            uint256 newTotal = credits[users[i]] + amounts[i];
            if (newTotal > maxCreditsPerUser) {
                revert ExceedsMaxCredits(newTotal, maxCreditsPerUser);
            }

            credits[users[i]] = newTotal;
            emit CreditsGranted(users[i], amounts[i]);
            
            unchecked { ++i; }
        }
    }

    /**
     * @notice Revoke credits from a user
     */
    function revokeCredits(address user, uint256 amount) external onlyOwner {
        uint256 current = credits[user];
        uint256 toRevoke = amount > current ? current : amount;
        credits[user] = current - toRevoke;
        emit CreditsRevoked(user, toRevoke);
    }

    /**
     * @notice Update max credits per user
     */
    function setMaxCreditsPerUser(uint256 _max) external onlyOwner {
        maxCreditsPerUser = _max;
    }

    /**
     * @notice Update minimum donation amount
     */
    function setMinDonationAmount(uint256 _min) external onlyOwner {
        minDonationAmount = _min;
    }

    /**
     * @notice Emergency drain pool to Safe
     */
    function drainPool(address to) external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        if (balance > 0) {
            token.safeTransfer(to, balance);
            emit PoolDrained(to, balance);
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ============================================
    // Fund the Pool
    // ============================================

    /**
     * @notice Anyone can fund the pool (but typically the treasury Safe)
     */
    function fundPool(uint256 amount) external {
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit PoolFunded(msg.sender, amount);
    }
}
