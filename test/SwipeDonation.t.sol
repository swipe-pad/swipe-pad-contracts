// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {SwipeDonation} from "../src/SwipeDonation.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract SwipeDonationTest is Test {
    // Declare events for expectEmit
    event Donation(address indexed donor, address indexed recipient, address indexed token, uint256 amount);
    event BatchDonation(address indexed donor, address indexed token, uint256 totalAmount, uint256 recipientCount);
    SwipeDonation public donation;
    ERC20Mock public token;

    address public owner = address(this);
    address public donor = makeAddr("donor");
    address public recipient1 = makeAddr("recipient1");
    address public recipient2 = makeAddr("recipient2");
    address public recipient3 = makeAddr("recipient3");

    uint256 public constant INITIAL_BALANCE = 1000 * 1e18;
    uint256 public constant DONATION_AMOUNT = 10 * 1e18;

    function setUp() public {
        // Deploy contracts
        donation = new SwipeDonation(owner);
        token = new ERC20Mock("cUSD", "cUSD");

        // Setup donor with tokens
        token.mint(donor, INITIAL_BALANCE);

        // Approve donation contract
        vm.prank(donor);
        token.approve(address(donation), type(uint256).max);
    }

    // ============ Single Donation Tests ============

    function test_donate_success() public {
        vm.prank(donor);
        donation.donate(address(token), recipient1, DONATION_AMOUNT);

        assertEq(token.balanceOf(recipient1), DONATION_AMOUNT);
        assertEq(token.balanceOf(donor), INITIAL_BALANCE - DONATION_AMOUNT);
    }

    function test_donate_emitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit Donation(donor, recipient1, address(token), DONATION_AMOUNT);

        vm.prank(donor);
        donation.donate(address(token), recipient1, DONATION_AMOUNT);
    }

    function test_donate_revertsOnZeroAmount() public {
        vm.prank(donor);
        vm.expectRevert(SwipeDonation.ZeroAmount.selector);
        donation.donate(address(token), recipient1, 0);
    }

    function test_donate_revertsOnZeroAddress() public {
        vm.prank(donor);
        vm.expectRevert(SwipeDonation.ZeroAddress.selector);
        donation.donate(address(token), address(0), DONATION_AMOUNT);
    }

    function test_donate_revertsOnZeroToken() public {
        vm.prank(donor);
        vm.expectRevert(SwipeDonation.ZeroAddress.selector);
        donation.donate(address(0), recipient1, DONATION_AMOUNT);
    }

    // ============ Batch Donation Tests ============

    function test_batchDonate_success() public {
        address[] memory recipients = new address[](3);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        recipients[2] = recipient3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10 * 1e18;
        amounts[1] = 20 * 1e18;
        amounts[2] = 30 * 1e18;

        vm.prank(donor);
        donation.batchDonate(address(token), recipients, amounts);

        assertEq(token.balanceOf(recipient1), 10 * 1e18);
        assertEq(token.balanceOf(recipient2), 20 * 1e18);
        assertEq(token.balanceOf(recipient3), 30 * 1e18);
        assertEq(token.balanceOf(donor), INITIAL_BALANCE - 60 * 1e18);
    }

    function test_batchDonate_emitsBatchEvent() public {
        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10 * 1e18;
        amounts[1] = 15 * 1e18;

        vm.expectEmit(true, true, true, true);
        emit BatchDonation(donor, address(token), 25 * 1e18, 2);

        vm.prank(donor);
        donation.batchDonate(address(token), recipients, amounts);
    }

    function test_batchDonate_revertsOnArrayMismatch() public {
        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = DONATION_AMOUNT;

        vm.prank(donor);
        vm.expectRevert(SwipeDonation.ArrayLengthMismatch.selector);
        donation.batchDonate(address(token), recipients, amounts);
    }

    function test_batchDonate_revertsOnBatchTooLarge() public {
        address[] memory recipients = new address[](51);
        uint256[] memory amounts = new uint256[](51);

        for (uint256 i = 0; i < 51; i++) {
            recipients[i] = makeAddr(string(abi.encodePacked("recipient", i)));
            amounts[i] = 1e18;
        }

        vm.prank(donor);
        vm.expectRevert(abi.encodeWithSelector(SwipeDonation.BatchTooLarge.selector, 51, 50));
        donation.batchDonate(address(token), recipients, amounts);
    }

    function test_batchDonate_revertsOnZeroToken() public {
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = DONATION_AMOUNT;

        vm.prank(donor);
        vm.expectRevert(SwipeDonation.ZeroAddress.selector);
        donation.batchDonate(address(0), recipients, amounts);
    }

    // ============ Pause Tests ============

    function test_pause_blocksdonations() public {
        donation.pause();

        vm.prank(donor);
        vm.expectRevert();
        donation.donate(address(token), recipient1, DONATION_AMOUNT);
    }

    function test_unpause_allowsDonations() public {
        donation.pause();
        donation.unpause();

        vm.prank(donor);
        donation.donate(address(token), recipient1, DONATION_AMOUNT);

        assertEq(token.balanceOf(recipient1), DONATION_AMOUNT);
    }

    function test_pauseOnlyOwner() public {
        vm.prank(donor);
        vm.expectRevert();
        donation.pause();
    }

    // ============ Gas Benchmark ============

    function test_gasBenchmark_singleDonation() public {
        vm.prank(donor);
        uint256 gasBefore = gasleft();
        donation.donate(address(token), recipient1, DONATION_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Single donation gas:", gasUsed);
    }

    function test_gasBenchmark_batchOf10() public {
        address[] memory recipients = new address[](10);
        uint256[] memory amounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            recipients[i] = makeAddr(string(abi.encodePacked("recipient", i)));
            amounts[i] = 1e18;
        }

        token.mint(donor, 100 * 1e18); // Extra tokens

        vm.prank(donor);
        uint256 gasBefore = gasleft();
        donation.batchDonate(address(token), recipients, amounts);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Batch of 10 gas:", gasUsed);
    }
}
