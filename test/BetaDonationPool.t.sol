// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BetaDonationPool} from "../src/BetaDonationPool.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract BetaDonationPoolTest is Test {
    BetaDonationPool public pool;
    ERC20Mock public token;

    address public owner = address(this);
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public recipient1 = makeAddr("recipient1");
    address public recipient2 = makeAddr("recipient2");
    address public recipient3 = makeAddr("recipient3");

    uint256 public constant MAX_CREDITS = 25 * 1e16; // 25 credits @ $0.01 = 0.25 cUSD
    uint256 public constant MIN_DONATION = 1e16; // $0.01 minimum
    uint256 public constant POOL_FUNDING = 1000 * 1e18; // 1000 cUSD

    function setUp() public {
        // Deploy token and pool
        token = new ERC20Mock("cUSD", "cUSD");
        pool = new BetaDonationPool(
            address(token),
            owner,
            MAX_CREDITS,
            MIN_DONATION
        );

        // Fund the pool
        token.mint(address(this), POOL_FUNDING);
        token.approve(address(pool), POOL_FUNDING);
        pool.fundPool(POOL_FUNDING);
    }

    // ============ Credit Management Tests ============

    function test_grantCredits() public {
        pool.grantCredits(user1, 10 * 1e16);
        assertEq(pool.credits(user1), 10 * 1e16);
    }

    function test_grantCredits_cannotExceedMax() public {
        pool.grantCredits(user1, MAX_CREDITS);
        
        vm.expectRevert();
        pool.grantCredits(user1, 1); // Even 1 wei over max should fail
    }

    function test_constructor_revertsOnZeroToken() public {
        vm.expectRevert(BetaDonationPool.ZeroAddress.selector);
        new BetaDonationPool(address(0), owner, MAX_CREDITS, MIN_DONATION);
    }

    function test_batchGrantCredits() public {
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10 * 1e16;
        amounts[1] = 15 * 1e16;

        pool.batchGrantCredits(users, amounts);

        assertEq(pool.credits(user1), 10 * 1e16);
        assertEq(pool.credits(user2), 15 * 1e16);
    }

    function test_revokeCredits() public {
        pool.grantCredits(user1, 10 * 1e16);
        pool.revokeCredits(user1, 5 * 1e16);
        assertEq(pool.credits(user1), 5 * 1e16);
    }

    // ============ Donation Tests ============

    function test_donate_success() public {
        pool.grantCredits(user1, 10 * 1e16);

        vm.prank(user1);
        pool.donate(recipient1, 5 * 1e16);

        assertEq(pool.credits(user1), 5 * 1e16);
        assertEq(token.balanceOf(recipient1), 5 * 1e16);
    }

    function test_donate_failsWithoutCredits() public {
        vm.prank(user1);
        vm.expectRevert();
        pool.donate(recipient1, 1e16);
    }

    function test_donate_failsBelowMinimum() public {
        pool.grantCredits(user1, 10 * 1e16);

        vm.prank(user1);
        vm.expectRevert();
        pool.donate(recipient1, MIN_DONATION - 1);
    }

    function test_batchDonate_success() public {
        pool.grantCredits(user1, 25 * 1e16);

        address[] memory recipients = new address[](3);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        recipients[2] = recipient3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 5 * 1e16;
        amounts[1] = 5 * 1e16;
        amounts[2] = 5 * 1e16;

        vm.prank(user1);
        pool.batchDonate(recipients, amounts);

        assertEq(pool.credits(user1), 10 * 1e16);
        assertEq(token.balanceOf(recipient1), 5 * 1e16);
        assertEq(token.balanceOf(recipient2), 5 * 1e16);
        assertEq(token.balanceOf(recipient3), 5 * 1e16);
    }

    // ============ Security Tests ============

    function test_onlyOwnerCanGrantCredits() public {
        vm.prank(user1);
        vm.expectRevert();
        pool.grantCredits(user2, 10 * 1e16);
    }

    function test_pause_blocksDonations() public {
        pool.grantCredits(user1, 10 * 1e16);
        pool.pause();

        vm.prank(user1);
        vm.expectRevert();
        pool.donate(recipient1, 5 * 1e16);
    }

    function test_drainPool() public {
        address treasury = makeAddr("treasury");
        uint256 balanceBefore = token.balanceOf(address(pool));

        pool.drainPool(treasury);

        assertEq(token.balanceOf(treasury), balanceBefore);
        assertEq(token.balanceOf(address(pool)), 0);
    }

    // ============ Gas Benchmarks ============

    function test_gasBenchmark_singleDonation() public {
        pool.grantCredits(user1, 10 * 1e16);

        vm.prank(user1);
        uint256 gasBefore = gasleft();
        pool.donate(recipient1, 5 * 1e16);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Single donation from pool gas:", gasUsed);
    }

    function test_gasBenchmark_batchOf10() public {
        pool.grantCredits(user1, 25 * 1e16);

        address[] memory recipients = new address[](10);
        uint256[] memory amounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            recipients[i] = makeAddr(string(abi.encodePacked("recipient", i)));
            amounts[i] = 1e16;
        }

        vm.prank(user1);
        uint256 gasBefore = gasleft();
        pool.batchDonate(recipients, amounts);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Batch of 10 from pool gas:", gasUsed);
    }
}
