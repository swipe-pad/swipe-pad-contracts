// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title SwipeDonation
 * @notice Gas-efficient batch donation contract for SwipePad
 * @dev Enables single or batched ERC20 donations with event emission for off-chain indexing.
 *      Designed for Celo (cUSD/USDC) and Base (USDC) networks.
 */
contract SwipeDonation is Ownable, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Maximum recipients per batch to prevent gas limit issues
    uint256 public constant MAX_BATCH_SIZE = 50;

    /// @notice Emitted for each individual donation
    event Donation(
        address indexed donor,
        address indexed recipient,
        address indexed token,
        uint256 amount
    );

    /// @notice Emitted after a batch donation completes
    event BatchDonation(
        address indexed donor,
        address indexed token,
        uint256 totalAmount,
        uint256 recipientCount
    );

    /// @notice Emitted when the contract is paused/unpaused
    event EmergencyPause(bool paused);

    error ArrayLengthMismatch();
    error BatchTooLarge(uint256 size, uint256 max);
    error ZeroAmount();
    error ZeroAddress();

    constructor(address initialOwner) Ownable(initialOwner) {}

    /**
     * @notice Donate tokens to a single recipient
     * @param token ERC20 token address (e.g., cUSD, USDC)
     * @param recipient Address to receive the donation
     * @param amount Amount of tokens to donate
     */
    function donate(
        address token,
        address recipient,
        uint256 amount
    ) external whenNotPaused {
        if (token == address(0)) revert ZeroAddress();
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        IERC20(token).safeTransferFrom(msg.sender, recipient, amount);
        emit Donation(msg.sender, recipient, token, amount);
    }

    /**
     * @notice Donate tokens to multiple recipients in a single transaction
     * @param token ERC20 token address (e.g., cUSD, USDC)
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts for each recipient
     * @dev Arrays must be same length. Max 50 recipients per batch.
     *      Caller must have approved this contract to spend total amount.
     */
    function batchDonate(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external whenNotPaused {
        uint256 length = recipients.length;

        if (token == address(0)) revert ZeroAddress();
        if (length != amounts.length) revert ArrayLengthMismatch();
        if (length > MAX_BATCH_SIZE) revert BatchTooLarge(length, MAX_BATCH_SIZE);

        uint256 totalAmount;

        for (uint256 i; i < length; ) {
            address recipient = recipients[i];
            uint256 amount = amounts[i];

            if (recipient == address(0)) revert ZeroAddress();
            if (amount == 0) revert ZeroAmount();

            IERC20(token).safeTransferFrom(msg.sender, recipient, amount);
            emit Donation(msg.sender, recipient, token, amount);

            totalAmount += amount;

            unchecked {
                ++i;
            }
        }

        emit BatchDonation(msg.sender, token, totalAmount, length);
    }

    /**
     * @notice Emergency pause - stops all donations
     * @dev Only owner (multisig) can call
     */
    function pause() external onlyOwner {
        _pause();
        emit EmergencyPause(true);
    }

    /**
     * @notice Resume donations after pause
     * @dev Only owner (multisig) can call
     */
    function unpause() external onlyOwner {
        _unpause();
        emit EmergencyPause(false);
    }
}
