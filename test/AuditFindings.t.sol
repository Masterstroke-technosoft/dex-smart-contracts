// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {Test} from "forge-std/Test.sol";
import {WMSTC} from "../src/WMSTC.sol";
import {MinimalPositionDescriptor} from "../src/MinimalPositionDescriptor.sol";

contract AuditFindingsTest is Test {
    WMSTC wmstc;
    MinimalPositionDescriptor descriptor;

    address owner = address(0x0E);
    address holder = address(0xA11CE);
    address spender = address(0xB0B);

    function setUp() public {
        wmstc = new WMSTC();
        descriptor = new MinimalPositionDescriptor("RapidEX V3 liquidity position", owner);

        vm.deal(holder, 100 ether);
        vm.prank(holder);
        wmstc.deposit{value: 50 ether}();
    }


    function test_finding4_liveAllowanceCannotBeRaced() public {
        vm.prank(holder);
        wmstc.approve(spender, 10 ether);

        vm.prank(spender);
        wmstc.transferFrom(holder, spender, 10 ether);

        vm.prank(holder);
        vm.expectRevert("WMSTC: allowance changed");
        wmstc.compareAndApprove(spender, 10 ether, 5 ether);
    }

    function test_finding4_approveStaysErc20Compliant() public {
        vm.startPrank(holder);
        wmstc.approve(spender, 10 ether);
        wmstc.approve(spender, 5 ether);
        vm.stopPrank();

        assertEq(wmstc.allowance(holder, spender), 5 ether, "overwrite honoured");
    }


    function test_finding5_freezeMakesMetadataImmutable() public {
        vm.startPrank(owner);
        descriptor.setBaseDescription("still editable");
        descriptor.freezeMetadata();

        vm.expectRevert(MinimalPositionDescriptor.MetadataIsFrozen.selector);
        descriptor.setBaseDescription("too late");
        vm.stopPrank();

        assertTrue(descriptor.metadataFrozen(), "freeze is sticky");
        assertEq(descriptor.baseDescription(), "still editable", "last value survives");
    }

    function test_finding5_mutableUntilFrozen() public {
        vm.prank(owner);
        descriptor.setBaseDescription("v2");

        assertEq(descriptor.baseDescription(), "v2");
        assertFalse(descriptor.metadataFrozen(), "not frozen until called");
    }

    function test_finding5_tokenUriIsAResolvableDataUri() public view {
        string memory uri = descriptor.tokenURI(address(0xdead), 42);
        bytes memory raw = bytes(uri);

        string memory prefix = "data:application/json;base64,";
        bytes memory want = bytes(prefix);
        assertGt(raw.length, want.length, "uri is more than its prefix");

        for (uint256 i = 0; i < want.length; i++) {
            assertEq(raw[i], want[i], "data URI prefix");
        }
    }


    function test_finding9_totalSupplyTracksNativeBalanceIncludingForcedSends() public {
        uint256 credited = wmstc.balanceOf(holder);
        assertEq(wmstc.totalSupply(), credited, "starts in agreement");

        vm.deal(address(wmstc), address(wmstc).balance + 7 ether);

        assertEq(wmstc.totalSupply(), credited + 7 ether, "totalSupply follows the balance");
        assertEq(wmstc.balanceOf(holder), credited, "no user was credited the forced send");
    }


    function test_finding10_descriptorOwnershipIsTwoStep() public {
        address next = address(0xC0FFEE);

        vm.prank(owner);
        descriptor.transferOwnership(next);
        assertEq(descriptor.owner(), owner, "not moved until accepted");

        vm.prank(next);
        descriptor.acceptOwnership();
        assertEq(descriptor.owner(), next, "two-step handoff completes");
    }

    function test_finding10_onlyPendingOwnerCanAccept() public {
        vm.prank(owner);
        descriptor.transferOwnership(address(0xC0FFEE));

        vm.prank(address(0xBAD));
        vm.expectRevert();
        descriptor.acceptOwnership();

        assertEq(descriptor.owner(), owner, "role did not move");
    }

    function test_finding10_onlyOwnerSetsDescription() public {
        vm.prank(holder);
        vm.expectRevert();
        descriptor.setBaseDescription("not yours");
    }
}
