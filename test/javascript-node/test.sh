#!/usr/bin/env bash
# Smoke test for the javascript-node template. Runs inside the dev container.
# Usage: test.sh <template-id> [full|nodb]
set -euo pipefail
# shellcheck source=../test-utils/test-utils.sh
source "$(dirname "$0")/test-utils.sh"
MODE=${2:-full}
EXPECTED_TASKS="1. Verify database schema and data|2. Build SQL Database project|3. Publish SQL Database project"

checkTools "$EXPECTED_TASKS"
if [ "$MODE" = full ]; then
    checkDatabase
    if [ "${SMOKE_NO_NPM_REGISTRY:-}" = 1 ]; then
        skip "S7 mssql sample prints 24" "SMOKE_NO_NPM_REGISTRY=1: registry.npmjs.org is unreachable from this network"
    else
        check "S7 npm install" npm install --prefix "$SMOKE_DIR" --no-audit --no-fund
        checkEquals "S7 mssql sample prints 24" 24 node "$SMOKE_DIR/index.js"
    fi
fi
reportResults
