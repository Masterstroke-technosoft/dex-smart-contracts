#!/usr/bin/env bash
set -euo pipefail
# Static analysis with Slither. Requires: pip install slither-analyzer
echo "Running Slither static analysis..."
slither . --exclude-dependencies --filter-paths "lib/" || true
