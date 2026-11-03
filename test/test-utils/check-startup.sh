#!/usr/bin/env bash
# Exercises the real post-create scripts with command doubles; no Docker or database required.
set -euo pipefail

cd "$(dirname "$0")/../.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/work/.devcontainer/sql"

cat >"$tmp/bin/mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
tool=$(basename "$0")
event=$tool
case $tool in
    sqlcmd)
        database="" query=""
        while [ "$#" -gt 0 ]; do
            case $1 in
                -d) database=$2; shift ;;
                -Q) query=$2; shift ;;
            esac
            shift
        done
        [ "${SQLCMDPASSWORD:-}" = startup-test-password ]
        case $query in
            "SELECT 1") event="wait:$database" ;;
            "IF DB_ID('Library') IS NULL CREATE DATABASE [Library];")
                [ "$database" = master ]
                event=create
                ;;
            *) echo "Unexpected query: $query" >&2; exit 2 ;;
        esac
        ;;
    dotnet) [ "$*" = "build database/Library -nodeReuse:false" ]; event=build ;;
    sqlpackage)
        [[ " $* " == *" /Action:Publish "* ]]
        [[ " $* " == *" /TargetDatabaseName:Library "* ]]
        event=publish
        ;;
    sleep) exit 0 ;;
    *) echo "Unexpected tool: $tool" >&2; exit 2 ;;
esac
echo "$event" >>"$STARTUP_TRACE"
if [ "$event" = "$FAIL_AT" ]; then echo "Injected failure: $event" >&2; exit 1; fi
if [ "$RETRY" = yes ] && [[ $event == wait:* ]] && [ "$(grep -cFx "$event" "$STARTUP_TRACE")" -eq 1 ]; then
    echo "Injected transient readiness failure: $event" >&2
    exit 1
fi
if [ "$event" = create ]; then touch "$STARTUP_DB"; fi
if [ "$event" = wait:Library ] || [ "$event" = publish ]; then test -f "$STARTUP_DB"; fi
MOCK
chmod +x "$tmp/bin/mock"
for tool in sqlcmd dotnet sqlpackage sleep; do ln -s mock "$tmp/bin/$tool"; done

export PATH="$tmp/bin:$PATH" MSSQL_SA_PASSWORD=startup-test-password
export STARTUP_TRACE="$tmp/trace" STARTUP_DB="$tmp/database" FAIL_AT="" RETRY=no
success=$'wait:master\nbuild\ncreate\nwait:Library\npublish'

run() { # TEMPLATE FAILURE-EVENT EXPECTED-TRACE EXPECTED-DIAGNOSTIC
    local template=$1 expected=$3 diagnostic=$4 rc=0
    FAIL_AT=$2
    : >"$STARTUP_TRACE"
    rm -f "$STARTUP_DB"
    cp "src/$template/.devcontainer/sql/postCreateCommand.sh" "$tmp/work/.devcontainer/sql/"
    bash "$tmp/work/.devcontainer/sql/postCreateCommand.sh" >"$tmp/output" 2>&1 || rc=$?
    if [ "$(cat "$STARTUP_TRACE")" != "$expected" ]; then
        echo "FAILED: $template ($FAIL_AT): unexpected startup order" >&2
        cat "$STARTUP_TRACE" "$tmp/output" >&2
        exit 1
    fi
    if [ -n "$diagnostic" ]; then
        if [ "$rc" -eq 0 ] || ! grep -qF "failed during: $diagnostic" "$tmp/output"; then
            echo "FAILED: $template ($FAIL_AT): missing failure diagnostic" >&2; cat "$tmp/output" >&2; exit 1;
        fi
    elif [ "$rc" -ne 0 ]; then
        echo "FAILED: $template: startup exited $rc" >&2; cat "$tmp/output" >&2; exit 1
    fi
}

for template in dotnet dotnet-aspire javascript-node python; do
    run "$template" "" "$success" ""
    # Publishing again must use the same guarded provisioning query and database target.
    bash "$tmp/work/.devcontainer/sql/postCreateCommand.sh" >"$tmp/output" 2>&1
    [ "$(cat "$STARTUP_TRACE")" = "$success"$'\n'"$success" ]
    run "$template" wait:master "$(printf 'wait:master\n%.0s' {1..10})" "wait for Azure SQL Database"
    run "$template" build $'wait:master\nbuild' "build database/Library"
    run "$template" create $'wait:master\nbuild\ncreate' "provision Library through master"
    run "$template" wait:Library "$(printf 'wait:master\nbuild\ncreate\n'; printf 'wait:Library\n%.0s' {1..10})" "wait for Library"
    run "$template" publish "$success" "publish database/Library"
    RETRY=yes
    run "$template" "" $'wait:master\nwait:master\nbuild\ncreate\nwait:Library\nwait:Library\npublish' ""
    RETRY=no
    echo "ok: $template: provisioning order, re-publish, bounded waits, failure propagation, readiness retries"
done
