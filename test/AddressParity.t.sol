// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {Test} from "forge-std/Test.sol";

contract Dummy {
    uint256 public x;

    constructor(uint256 x_) {
        x = x_;
    }
}

contract Other {
    bytes32 public a;
    bytes32 public b;

    constructor(string memory s_) {
        a = keccak256(bytes(s_));
        b = keccak256(abi.encode(a, a));
    }
}

contract AddressParityTest is Test {
    address constant DEPLOYER = 0x20dC715651E633725131131523DB75CB9504b50d;

    function test_predictionMatchesActualDeployment() public {
        vm.setNonce(DEPLOYER, 0);

        for (uint64 i = 0; i < 5; i++) {
            address predicted = vm.computeCreateAddress(DEPLOYER, i);
            vm.prank(DEPLOYER);
            address actual = address(new Dummy(i));
            assertEq(actual, predicted, "predicted matches deployed");
        }
    }

    function test_addressIndependentOfCodeAndArgs() public {
        address d1 = address(0xD1);
        address d2 = address(0xD2);

        vm.prank(d1);
        address a = address(new Dummy(111));

        vm.prank(d2);
        address b = address(new Other("totally different bytecode and args"));

        assertEq(a, vm.computeCreateAddress(d1, 0), "Dummy matches prediction");
        assertEq(b, vm.computeCreateAddress(d2, 0), "Other matches prediction");
    }

    function test_differentDeployerDiverges() public {
        address other = address(0xBEEF);

        vm.setNonce(DEPLOYER, 0);
        vm.prank(DEPLOYER);
        address a = address(new Dummy(1));

        vm.setNonce(other, 0);
        vm.prank(other);
        address b = address(new Dummy(1));

        assertTrue(a != b, "different deployer breaks parity");
    }

    function test_nonceDriftBreaksParity() public {
        vm.setNonce(DEPLOYER, 0);
        vm.prank(DEPLOYER);
        address onChainA = address(new Dummy(1));

        vm.setNonce(DEPLOYER, 1);
        vm.prank(DEPLOYER);
        address onChainB = address(new Dummy(1));

        assertTrue(onChainA != onChainB, "nonce drift changes the address");
    }
}
