#!/usr/bin/env bash
# Smoke test for the dotnet and dotnet-aspire templates. Runs inside the dev container.
# Usage: test.sh <template-id> [full|nodb]
set -euo pipefail
# shellcheck source=../test-utils/test-utils.sh
source "$(dirname "$0")/test-utils.sh"
TEMPLATE_ID=$1
MODE=${2:-full}
EXPECTED_TASKS="1. Verify database schema and data|2. Build SQL Database project|3. Publish SQL Database project|4. Trust .NET HTTPS certificate"

runSample() {
    dotnet build "$SMOKE_DIR/SmokeTest.csproj" -o "$SMOKE_DIR/out" >&2
    dotnet "$SMOKE_DIR/out/SmokeTest.dll"
}

checkTools "$EXPECTED_TASKS"
if [ "$TEMPLATE_ID" = dotnet-aspire ]; then
    checkMatches "S7 aspire 13.5.x" '^13\.5\.' aspire --version
    checkNative "S1/S2 native aspire" "$(command -v aspire)"
    checkMatches "S7 Aspire project templates installed" 'aspire-apphost' dotnet new list aspire
fi
if [ "$MODE" = full ]; then
    checkDatabase
    checkEquals "S7 SqlClient sample prints 24" 24 runSample
fi
reportResults
