// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal Echidna invariant harness. Extend with real pool/router
///         invariants (e.g. k never decreases on a fee-bearing swap, liquidity
///         accounting never underflows) once contracts are wired in.
contract EchidnaInvariants {
    uint256 internal k = 1_000_000;

    function echidna_k_is_positive() public view returns (bool) {
        return k > 0;
    }
}
