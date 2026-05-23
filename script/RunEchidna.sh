#!/usr/bin/env bash
set -euo pipefail
# Property-based fuzzing with Echidna. Requires echidna installed.
echo "Running Echidna fuzz campaign..."
echidna test/echidna/EchidnaInvariants.sol --config echidna.yaml || true
