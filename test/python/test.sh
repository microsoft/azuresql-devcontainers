#!/usr/bin/env bash
# Smoke test for the python template. Runs inside the dev container.
# Usage: test.sh <template-id> [full|nodb]
set -euo pipefail
# shellcheck source=../test-utils/test-utils.sh
source "$(dirname "$0")/test-utils.sh"
MODE=${2:-full}
EXPECTED_TASKS="1. Verify database schema and data|2. Build SQL Database project|3. Publish SQL Database project"

pipVersion() { python -c 'import importlib.metadata as m; print(m.version("mssql-python"))'; }

checkTools "$EXPECTED_TASKS"
checkEquals "S7 mssql-python installed" "$(sed -n 's/^mssql-python==//p' "$SMOKE_DIR/requirements.txt")" pipVersion
if [ "$MODE" = full ]; then
    checkDatabase
    checkEquals "S7 mssql-python sample prints 24" 24 python "$SMOKE_DIR/test_sql_connection.py"
fi
reportResults
