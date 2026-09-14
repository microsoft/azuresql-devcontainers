#!/usr/bin/env bash
# Assertions shared by the per-template smoke tests. Sourced inside the dev container.
# Every check prints "PASS: <label>" or "FAIL: <label>"; reportResults exits 1 if any failed.
set -euo pipefail

FAILED=()
SKIPPED=()
SMOKE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKSPACE=$(cd "$SMOKE_DIR/.." && pwd)
DACPAC=$WORKSPACE/database/Library/bin/Debug/Library.dacpac

# S5: record what the up left behind now, before any check (S9 builds the project again).
BUILT_BY_UP=no
if [ -f "$DACPAC" ] && [ "$DACPAC" -nt "$SMOKE_DIR/.before-up" ]; then BUILT_BY_UP=yes; fi

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

# The machine an ELF file is built for, from its header: aarch64, x86_64, or other.
elfMachine() {
    local header
    header=$(od -An -tx1 -N20 "$1" | tr -d ' \n')
    case $header in
        7f454c46*b700) echo aarch64 ;;
        7f454c46*3e00) echo x86_64 ;;
        *) echo "other($header)" ;;
    esac
}

# checkNative LABEL FILE: FILE is built for this container's architecture, not run under emulation.
checkNative() {
    local machine
    machine=$(elfMachine "$(readlink -f "$2")") || machine="unreadable"
    if [ "$machine" = "$EXPECTED_ARCH" ]; then pass "$1"; else fail "$1" "$2 is $machine, container is $EXPECTED_ARCH"; fi
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

# The SQL Database Projects extension finds the .NET SDK through this setting.
sdkSettingHasDotnet() {
    local dir
    dir=$(sed -n 's/.*"sqlDatabaseProjects.dotnetSDK Location": "\([^"]*\)".*/\1/p' "$WORKSPACE/.devcontainer/devcontainer.json")
    echo "sqlDatabaseProjects.dotnetSDK Location: $dir"
    [ -n "$dir" ] && [ -x "$dir/dotnet" ] && [ -n "$(ls "$dir/sdk")" ]
}

dacpacModel() { unzip -p "$DACPAC" model.xml | sed -n 2p; }

# Microsoft's package (version like 2.90.0-1~bookworm), not a distribution's older build.
azureCliFromMicrosoft() {
    local version
    version=$(dpkg-query -W -f '${Version}' azure-cli)
    echo "azure-cli $version"
    [[ $version =~ -1~[a-z]+$ ]]
}

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
    checkNative "S1/S2 native sqlcmd" "$(command -v sqlcmd)"
    checkNative "S1/S2 native dotnet host" "$(command -v dotnet)"
    checkNative "S1/S2 native sqlpackage launcher" "$(command -v sqlpackage)"
    check "S6 Azure CLI from Microsoft's repository" azureCliFromMicrosoft
    checkMatches "S6 Bicep CLI" '^Bicep CLI version ' bicep --version
    checkNative "S1/S2 native bicep" "$(command -v bicep)"
    checkNative "S1/S2 native azd" "$(command -v azd)"
    checkNative "S1/S2 native docker CLI" "$(command -v docker)"
    check "S9 build against SqlAzureV12" dotnet build "$WORKSPACE/database/Library"
    checkMatches "S9 dacpac targets SqlAzureV12" 'DspName="Microsoft\.Data\.Tools\.Schema\.Sql\.SqlAzureV12DatabaseSchemaProvider"' dacpacModel
    checkMatches "S9 dacpac model is case-insensitive" 'CollationCaseSensitive="False"' dacpacModel
    check "S10 fixture builds under Sql170" buildWithFixture Microsoft.Data.Tools.Schema.Sql.Sql170DatabaseSchemaProvider
    check "S10 Azure target rejects fixture with $S10_ERROR" azureTargetRejectsFixture
    checkEquals "S17 task labels" "$1" taskLabels
    check "S17 task 2 builds the project" runTask "2. Build SQL Database project"
    check "S17 SQL Database Projects SDK setting points at the SDK" sdkSettingHasDotnet
}

# S16: with an object the Azure target rejects, postCreateCommand.sh stops at the build and publishes
# nothing, even though a dacpac from the last good build is still there.
failedBuildNeverPublishes() {
    local copy out rc=0
    copy=$(mktemp -d "$SMOKE_DIR/s16.XXXX") # under the workspace, so a workspace NuGet.Config applies
    mkdir -p "$copy/.devcontainer/sql" "$copy/database"
    cp "$WORKSPACE/.devcontainer/sql/postCreateCommand.sh" "$copy/.devcontainer/sql/"
    cp -R "$WORKSPACE/database/Library" "$copy/database/Library"
    cp "$SMOKE_DIR"/fixtures/azure-incompatible/*.sql "$copy/database/Library/"
    out=$(bash "$copy/.devcontainer/sql/postCreateCommand.sh" 2>&1) || rc=$?
    rm -rf "$copy"
    echo "exit $rc; last lines: $(tail -n 2 <<<"$out")"
    [ "$rc" -ne 0 ] && grep -q "failed during: build database/Library" <<<"$out" && ! grep -q "Successfully published" <<<"$out"
}

wrongPasswordFailsLoudly() {
    local out rc=0 start=$SECONDS
    out=$(MSSQL_SA_PASSWORD='Wrong-Passw0rd' timeout 180 bash "$WORKSPACE/.devcontainer/sql/postCreateCommand.sh" 2>&1) || rc=$?
    echo "exit $rc after $((SECONDS - start)) s; last lines: $(tail -n 2 <<<"$out")"
    [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] && grep -q "failed during: wait for SQL Server" <<<"$out"
}

# S18: the LocalDev connection profile must carry credentials that work. VS Code writes these settings
# into the container's Machine settings.json verbatim, so a ${env:...} placeholder arrives as an empty
# password and the profile cannot connect.
profileAuthenticates() {
    local field
    for field in "${PROFILE_SERVER:-}" "${PROFILE_USER:-}" "${PROFILE_PASSWORD:-}"; do
        if [ -z "$field" ]; then echo "the LocalDev profile has an empty server, user, or password" >&2; return 1; fi
        # shellcheck disable=SC2016 # a literal ${ placeholder
        case $field in *'${'*) echo "the LocalDev profile still contains a placeholder: $field" >&2; return 1 ;; esac
    done
    SQLCMDPASSWORD=$PROFILE_PASSWORD sqlcmd -S "$PROFILE_SERVER" -U "$PROFILE_USER" -C -b -l 5 -Q "SELECT 1" >/dev/null
}

# Checks against the running SQL Server.
checkDatabase() {
    checkEquals "S4 engine major version 17" 17 sql "SELECT SERVERPROPERTY('ProductMajorVersion')"
    checkEquals "S4 edition" "Enterprise Developer Edition (64-bit)" sql "SELECT SERVERPROPERTY('Edition')"
    check "S5 dacpac built during this up" test "$BUILT_BY_UP" = yes
    checkLibraryCounts S5
    checkEquals "S5 view and procedure exist" 2 sql "SELECT COUNT(*) FROM Library.sys.objects WHERE object_id IN (OBJECT_ID('Library.dbo.vw_books_details'), OBJECT_ID('Library.dbo.stp_get_all_cowritten_books_by_author'))"
    check "S8 task 3 re-publishes" runTask "3. Publish SQL Database project"
    checkLibraryCounts S8
    check "S18 the LocalDev profile authenticates" profileAuthenticates
    check "S16 a failed build is never published" failedBuildNeverPublishes
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
