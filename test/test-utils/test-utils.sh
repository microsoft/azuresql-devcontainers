#!/usr/bin/env bash
# Assertions shared by the per-template smoke tests. Sourced inside the dev container.
# Every check prints "PASS: <label>" or "FAIL: <label>"; reportResults exits 1 if any failed.
set -euo pipefail

FAILED=()
SKIPPED=()
SMOKE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKSPACE=$(cd "$SMOKE_DIR/.." && pwd)

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1${2:+ ($2)}" >&2; FAILED+=("$1"); }
skip() { echo "SKIP: $1 ($2)"; SKIPPED+=("$1"); }

# check LABEL CMD...: CMD must exit 0.
check() {
    local label=$1; shift
    if "$@"; then pass "$label"; else fail "$label" "exit $?"; fi
}

# checkEquals LABEL EXPECTED CMD...: CMD must exit 0 and print exactly EXPECTED (whitespace-trimmed).
checkEquals() {
    local label=$1 expected=$2 out rc=0; shift 2
    out=$("$@") || rc=$?
    out=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<"$out")
    if [ "$rc" -eq 0 ] && [ "$out" = "$expected" ]; then pass "$label"; else fail "$label" "exit $rc, got '$out', want '$expected'"; fi
}

# checkMatches LABEL REGEX CMD...: CMD must exit 0 and its output must match the extended REGEX.
checkMatches() {
    local label=$1 regex=$2 out rc=0; shift 2
    out=$("$@" 2>&1) || rc=$?
    if [ "$rc" -eq 0 ] && grep -Eq -- "$regex" <<<"$out"; then pass "$label"; else fail "$label" "exit $rc, no match for /$regex/ in: $(tail -c 400 <<<"$out")"; fi
}

# checkExtension ID: the extension is installed in a VS Code server in this container.
checkExtension() {
    local dir
    for dir in "$HOME"/.vscode-server "$HOME"/.vscode-server-insiders "$HOME"/.vscode-remote; do
        if compgen -G "$dir/extensions/$1-*" >/dev/null; then pass "extension $1"; return 0; fi
    done
    fail "extension $1" "not found under any VS Code server in $HOME"
}

sql() { sqlcmd -S localhost -U sa -C -b -h -1 -W -Q "SET NOCOUNT ON; $1"; }

# The exact command of a VS Code task, run from its cwd.
runTask() {
    local task cwd
    task=$(jq -e --arg l "$1" '.tasks[] | select(.label == $l)' "$WORKSPACE/.vscode/tasks.json")
    cwd=$(jq -r '.options.cwd // "${workspaceFolder}"' <<<"$task")
    cwd=${cwd//\$\{workspaceFolder\}/$WORKSPACE}
    mapfile -t args < <(jq -r '.args // [] | .[]' <<<"$task")
    (cd "$cwd" && bash -c "$(jq -r .command <<<"$task") \"\$@\"" task "${args[@]}")
}

taskLabels() { jq -r '.tasks[].label' "$WORKSPACE/.vscode/tasks.json" | paste -sd'|' -; }

dacpacModel() { unzip -p "$WORKSPACE/database/Library/bin/Debug/Library.dacpac" model.xml | sed -n 2p; }

# S10: the fixture builds under Sql170 (so it is valid T-SQL) and fails under the project's own target.
buildWithFixture() { # DSP-override-or-empty
    local tmp rc=0
    tmp=$(mktemp -d "$SMOKE_DIR/s10.XXXX") # under the workspace, so a workspace NuGet.Config applies
    cp -R "$WORKSPACE/database/Library/." "$tmp/"
    rm -rf "${tmp:?}/bin" "${tmp:?}/obj"
    cp "$SMOKE_DIR"/fixtures/azure-incompatible/*.sql "$tmp/"
    if [ -n "$1" ]; then sed -i "s#<DSP>.*</DSP>#<DSP>$1</DSP>#" "$tmp/Library.sqlproj"; fi
    dotnet build "$tmp" 2>&1 || rc=$?
    rm -rf "$tmp"
    return "$rc"
}
azureTargetRejectsFixture() {
    local out rc=0
    out=$(buildWithFixture "") || rc=$?
    [ "$rc" -ne 0 ] && grep -q "$S10_ERROR" <<<"$out"
}

# Checks that need no SQL Server: run on every platform, including the arm64 CI job.
checkTools() { # EXPECTED-TASK-LABELS joined by |
    checkEquals "S1/S2 architecture" "$EXPECTED_ARCH" uname -m
    checkMatches "S6 sqlcmd v1.10.0" 'v?1\.10\.0' sqlcmd --version
    checkMatches "S6 sqlpackage 170.5.x" '^170\.5\.' sqlpackage /version
    checkMatches "S6 dotnet $EXPECTED_DOTNET_MAJOR.x" "^$EXPECTED_DOTNET_MAJOR\." dotnet --version
    check "S9 build against SqlAzureV12" dotnet build "$WORKSPACE/database/Library"
    checkMatches "S9 dacpac targets SqlAzureV12" 'DspName="Microsoft\.Data\.Tools\.Schema\.Sql\.SqlAzureV12DatabaseSchemaProvider"' dacpacModel
    checkMatches "S9 dacpac model is case-insensitive" 'CollationCaseSensitive="False"' dacpacModel
    check "S10 fixture builds under Sql170" buildWithFixture Microsoft.Data.Tools.Schema.Sql.Sql170DatabaseSchemaProvider
    check "S10 Azure target rejects fixture with $S10_ERROR" azureTargetRejectsFixture
    checkEquals "F8 task labels" "$1" taskLabels
}

wrongPasswordFailsLoudly() {
    local out rc=0 start=$SECONDS
    out=$(MSSQL_SA_PASSWORD='Wrong-Passw0rd' timeout 180 bash "$WORKSPACE/.devcontainer/sql/postCreateCommand.sh" 2>&1) || rc=$?
    echo "exit $rc after $((SECONDS - start)) s; last lines: $(tail -n 2 <<<"$out")"
    [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] && grep -q "failed during: wait for SQL Server" <<<"$out"
}

# Checks against the running SQL Server.
checkDatabase() {
    checkEquals "S4 engine major version 17" 17 sql "SELECT SERVERPROPERTY('ProductMajorVersion')"
    checkEquals "S4 edition" "Enterprise Developer Edition (64-bit)" sql "SELECT SERVERPROPERTY('Edition')"
    check "S5 dacpac built during this up" test "$WORKSPACE/database/Library/bin/Debug/Library.dacpac" -nt "$SMOKE_DIR/.before-up"
    checkLibraryCounts S5
    checkEquals "S5 view and procedure exist" 2 sql "SELECT COUNT(*) FROM Library.sys.objects WHERE object_id IN (OBJECT_ID('Library.dbo.vw_books_details'), OBJECT_ID('Library.dbo.stp_get_all_cowritten_books_by_author'))"
    check "S8 task 3 re-publishes" runTask "3. Publish SQL Database project"
    checkLibraryCounts S8
    check "S11 wrong password fails loudly" wrongPasswordFailsLoudly
}

checkLibraryCounts() {
    checkEquals "$1 5 authors" 5 sql "SELECT COUNT(*) FROM Library.dbo.authors"
    checkEquals "$1 24 books" 24 sql "SELECT COUNT(*) FROM Library.dbo.books"
    checkEquals "$1 24 books_authors" 24 sql "SELECT COUNT(*) FROM Library.dbo.books_authors"
}

reportResults() {
    if [ ${#FAILED[@]} -ne 0 ]; then
        echo "FAILED ${#FAILED[@]} check(s): ${FAILED[*]}" >&2
        exit 1
    fi
    echo "ALL PASSED${SKIPPED[0]:+ (skipped ${#SKIPPED[@]}: ${SKIPPED[*]})}"
}

export SQLCMDPASSWORD=${MSSQL_SA_PASSWORD:-}
S10_ERROR=SQL70015 # measured: "Keyword or statement option FILESTREAM is not supported for the targeted platform"
