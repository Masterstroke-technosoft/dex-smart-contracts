// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "../lib/v3-periphery-main/contracts/lens/QuoterV2.sol";

contract QuoterV2Importer is QuoterV2 {
    constructor(address factory, address wmst) QuoterV2(factory, wmst) {}
}
