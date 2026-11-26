// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {Test} from "forge-std/Test.sol";
import {WMSTC} from "../src/WMSTC.sol";

contract AllowanceSafetyTest is Test {
    WMSTC wmstc;

    address holder = address(0xA11CE);
    address spender = address(0xB0B);

    function setUp() public {
        wmstc = new WMSTC();

        vm.deal(holder, 1_000 ether);
        vm.prank(holder);
        wmstc.deposit{value: 500 ether}();
    }


    function test_sandwichReverts() public {
        vm.prank(holder);
        wmstc.approve(spender, 100 ether);

        vm.prank(spender);
        wmstc.transferFrom(holder, spender, 100 ether);

        vm.prank(holder);
        vm.expectRevert("WMSTC: allowance changed");
        wmstc.compareAndApprove(spender, 100 ether, 50 ether);

        assertEq(wmstc.allowance(holder, spender), 0, "no new allowance was issued");
        assertEq(wmstc.balanceOf(spender), 100 ether, "spender got the old allowance only");
    }

    function test_partialFrontRunAlsoReverts() public {
        vm.prank(holder);
        wmstc.approve(spender, 100 ether);

        vm.prank(spender);
        wmstc.transferFrom(holder, spender, 1 ether);

        vm.prank(holder);
        vm.expectRevert("WMSTC: allowance changed");
        wmstc.compareAndApprove(spender, 100 ether, 50 ether);
    }

    function test_plainApproveIsStillTheErc20Race() public {
        vm.prank(holder);
        wmstc.approve(spender, 100 ether);

        vm.prank(spender);
        wmstc.transferFrom(holder, spender, 100 ether);

        vm.prank(holder);
        wmstc.approve(spender, 50 ether);

        assertEq(wmstc.allowance(holder, spender), 50 ether, "old+new is reachable via plain approve");
    }


    function test_compareAndApproveSucceedsWhenNothingRaced() public {
        vm.startPrank(holder);
        wmstc.approve(spender, 100 ether);
        wmstc.compareAndApprove(spender, 100 ether, 50 ether);
        vm.stopPrank();

        assertEq(wmstc.allowance(holder, spender), 50 ether, "uncontested change applies");
    }

    function test_compareAndApproveFromZeroIsAFirstApproval() public {
        vm.prank(holder);
        wmstc.compareAndApprove(spender, 0, 100 ether);

        assertEq(wmstc.allowance(holder, spender), 100 ether);
    }

    function test_compareAndApproveCanRaiseAndRevoke() public {
        vm.startPrank(holder);
        wmstc.compareAndApprove(spender, 0, 100 ether);
        wmstc.compareAndApprove(spender, 100 ether, 250 ether);
        assertEq(wmstc.allowance(holder, spender), 250 ether, "raise");
        wmstc.compareAndApprove(spender, 250 ether, 0);
        assertEq(wmstc.allowance(holder, spender), 0, "revoke");
        vm.stopPrank();
    }


    function test_approveOverwritesLiveAllowance() public {
        vm.startPrank(holder);
        wmstc.approve(spender, 100 ether);
        wmstc.approve(spender, 50 ether);
        vm.stopPrank();

        assertEq(wmstc.allowance(holder, spender), 50 ether, "ERC-20 overwrite honoured");
    }

    function test_revokingIsAlwaysAllowed() public {
        vm.startPrank(holder);
        wmstc.approve(spender, 100 ether);
        wmstc.approve(spender, 0);
        vm.stopPrank();

        assertEq(wmstc.allowance(holder, spender), 0, "revoke must never be blocked");
    }


    function test_relativeHelpersStillWork() public {
        vm.startPrank(holder);
        wmstc.approve(spender, 100 ether);
        wmstc.increaseAllowance(spender, 25 ether);
        assertEq(wmstc.allowance(holder, spender), 125 ether);
        wmstc.decreaseAllowance(spender, 75 ether);
        assertEq(wmstc.allowance(holder, spender), 50 ether);
        vm.stopPrank();
    }

    function test_decreaseRevertsIfAlreadySpent() public {
        vm.prank(holder);
        wmstc.approve(spender, 100 ether);

        vm.prank(spender);
        wmstc.transferFrom(holder, spender, 100 ether);

        vm.prank(holder);
        vm.expectRevert("WMSTC: decrease below zero");
        wmstc.decreaseAllowance(spender, 100 ether);
    }


    function test_partialTransferFromStillDecrements() public {
        vm.prank(holder);
        wmstc.approve(spender, 100 ether);

        vm.prank(spender);
        wmstc.transferFrom(holder, spender, 40 ether);
        assertEq(wmstc.allowance(holder, spender), 60 ether);
    }

    function test_infiniteAllowanceNotDecremented() public {
        vm.prank(holder);
        wmstc.approve(spender, type(uint256).max);

        vm.prank(spender);
        wmstc.transferFrom(holder, spender, 10 ether);
        assertEq(wmstc.allowance(holder, spender), type(uint256).max, "infinite stays infinite");
    }


    function testFuzz_sandwichNeverLands(uint96 live, uint96 spent, uint96 wanted) public {
        uint256 liveAmt = bound(uint256(live), 1, 500 ether);
        uint256 spentAmt = bound(uint256(spent), 1, liveAmt);

        vm.prank(holder);
        wmstc.approve(spender, liveAmt);

        vm.prank(spender);
        wmstc.transferFrom(holder, spender, spentAmt);

        vm.prank(holder);
        vm.expectRevert("WMSTC: allowance changed");
        wmstc.compareAndApprove(spender, liveAmt, wanted);

        assertEq(
            wmstc.allowance(holder, spender),
            liveAmt - spentAmt,
            "allowance is only what the spend left behind"
        );
    }

    function testFuzz_uncontestedChangeApplies(uint96 from, uint96 to) public {
        vm.prank(holder);
        wmstc.compareAndApprove(spender, 0, from);

        vm.prank(holder);
        wmstc.compareAndApprove(spender, from, to);

        assertEq(wmstc.allowance(holder, spender), to);
    }
}
