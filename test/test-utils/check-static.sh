#!/usr/bin/env bash
# Promises every change must keep, checked without Docker. Runs in CI's static job and in test/gauntlet.sh.
#   M1 template ids, M2 target platform, M3 schema and seed (hash manifest), M7 LocalDev profile and port 1433,
#   the compose shape (engine, platform, edition, healthcheck, resources), and CI integrity (S15: the workflow
#   still runs the smoke test in full mode and still fails when it fails).
# Needs jq, ruby (YAML), shasum, and the Dev Container CLI (JSONC). Usage: check-static.sh [repo-dir]
set -euo pipefail

cd "${1:-$(dirname "$0")/../..}"
DEVCONTAINER=${DEVCONTAINER:-npx -y @devcontainers/cli@0.89.0}
TEMPLATES="dotnet dotnet-aspire javascript-node python"
WORKFLOW=.github/workflows/test-pr.yaml
ACTION=.github/actions/smoke-test/action.yaml
failures=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

ok() { echo "ok: $*"; }
bad() { echo "FAILED: $*" >&2; failures=$((failures + 1)); }
# expect LABEL CMD...: CMD must exit 0.
expect() {
    local label=$1
    shift
    if "$@"; then ok "$label"; else bad "$label"; fi
}
# The workflow uses YAML anchors. Psych 4 (Ruby 3.1+) refuses aliases unless asked; Psych 3 has no
# such keyword and raises ArgumentError for it, so try the new signature and fall back to the old.
yaml2json() {
    ruby -ryaml -rjson -e '
        begin
            doc = YAML.load_file(ARGV[0], aliases: true)
        rescue ArgumentError
            doc = YAML.load_file(ARGV[0])
        end
        puts JSON.generate(doc)' "$1"
}

# --- M1, M2, M3 ---------------------------------------------------------------------------------------------
idsUnchanged() {
    local t
    [ "$(for t in src/*/devcontainer-template.json; do jq -r .id "$t"; done | sort | paste -sd' ' -)" = "$TEMPLATES" ] || return 1
    for t in $TEMPLATES; do [ "$(jq -r .id "src/$t/devcontainer-template.json")" = "$t" ] || return 1; done
}
dspUnchanged() {
    local t
    for t in $TEMPLATES; do
        [ "$(grep -c '<DSP>Microsoft.Data.Tools.Schema.Sql.SqlAzureV12DatabaseSchemaProvider</DSP>' "src/$t/database/Library/Library.sqlproj")" = 1 ] || return 1
    done
}
sqlUnchanged() { # every source .sql file matches the committed manifest, and there are no others
    shasum -a 256 -c test/fixtures/library-sql.sha256 >"$tmp/sql.txt" || { grep -v ': OK$' "$tmp/sql.txt" >&2; return 1; }
    [ "$(git -c core.quotePath=false ls-files ':(glob)src/*/database/Library/**/*.sql' | wc -l)" -eq "$(wc -l <test/fixtures/library-sql.sha256)" ]
}
expect "M1 template ids are dotnet, dotnet-aspire, javascript-node, python" idsUnchanged
expect "M2 all 4 SQL projects target SqlAzureV12DatabaseSchemaProvider" dspUnchanged
expect "M3 the 28 Library .sql files match test/fixtures/library-sql.sha256" sqlUnchanged

# --- M7 and the compose shape ---------------------------------------------------------------------------------
localDev() { # TEMPLATE
    $DEVCONTAINER read-configuration --workspace-folder "src/$1" >"$tmp/config-$1.json" 2>"$tmp/config-$1.err" || { cat "$tmp/config-$1.err" >&2; return 1; }
    # The profile carries ${containerEnv:MSSQL_SA_PASSWORD}: the dev container CLI resolves it from the
    # container's environment at create time, so the password itself lives only in .env. ${env:...} does
    # NOT resolve (measured: it arrives as an empty string), and a literal password here would duplicate .env.
    sed -n 's/^MSSQL_SA_PASSWORD=//p' "src/$1/.devcontainer/.env" | grep -q . || return 1
    jq -e '.configuration
        | (.customizations.vscode.settings."mssql.connections"[]
            | select(.profileName == "LocalDev")
            | .password == "${containerEnv:MSSQL_SA_PASSWORD}" and .savePassword == true)
        and (.forwardPorts | index(1433))
        and (.customizations.vscode.extensions | index("ms-mssql.mssql"))
        and any(.customizations.vscode.settings."mssql.connections"[]; .profileName == "LocalDev" and .server == "localhost,1433")' \
        "$tmp/config-$1.json" >/dev/null
}
composeShape() { # TEMPLATE
    yaml2json "src/$1/.devcontainer/docker-compose.yml" | jq -e '(has("version") | not)
        and .services.db.image == "mcr.microsoft.com/mssql/server:2025-latest"
        and .services.db.platform == "linux/amd64"
        and .services.db.environment.MSSQL_PID == "EnterpriseDeveloper"
        and .services.db.restart == "unless-stopped"
        and (.services.db.healthcheck.test | tostring | contains("/opt/mssql-tools18/bin/sqlcmd"))
        and .services.db.deploy.resources.limits == {"cpus": "2", "memory": "2048M"}
        and (.services.db | has("container_name") | not)
        and .services.app.depends_on.db.condition == "service_healthy"
        and .services.app.network_mode == "service:db"' >/dev/null
}
for t in $TEMPLATES; do
    expect "M7/S18 $t: LocalDev profile resolves the .env password from containerEnv on localhost,1433, port 1433, ms-mssql.mssql" localDev "$t"
    expect "compose $t: SQL Server 2025 Enterprise Developer, amd64, restart, healthcheck, 2 CPU/2048M, app waits for healthy" composeShape "$t"
done

# --- S15: CI integrity ----------------------------------------------------------------------------------------
yaml2json "$WORKFLOW" >"$tmp/workflow.json"
yaml2json "$ACTION" >"$tmp/action.json"

pinned() { [ "$(git ls-files '.github/**' | xargs grep -hE '^\s*-?\s*uses:' | grep -vcE 'uses: (\./|[^@]+@[0-9a-f]{40}( |$))')" = 0 ]; }
triggers() {
    jq -e '(.true | has("pull_request") and has("schedule") and has("workflow_dispatch"))
        and .permissions == {"contents": "read", "pull-requests": "read"}
        and .jobs.test.strategy.matrix.runner == ["ubuntu-latest", "ubuntu-24.04-arm"]' "$tmp/workflow.json" >/dev/null
}
# Only these conditions may appear; `if: false` or any other condition on a job or step fails.
conditions() {
    [ "$(jq -c '[.. | objects | select(has("if")) | .if]' "$tmp/workflow.json" "$tmp/action.json" | paste -sd' ' -)" = \
        "[\"github.event_name == 'pull_request'\",\"needs.detect-changes.outputs.templates != '[]'\"] []" ]
}
noContinueOnError() { jq -e '[.. | objects | select(has("continue-on-error"))] | length == 0' "$tmp/workflow.json" "$tmp/action.json" >/dev/null; }
# No step may swallow a failure.
noSwallowedFailures() {
    local runs
    runs=$(jq -r '.. | objects | .run? // empty' "$tmp/workflow.json" "$tmp/action.json") || return 2
    [ -n "$runs" ] || return 2
    ! grep -nE '\|\||set[[:space:]]+\+[a-z]*e|exit[[:space:]]+0|;[[:space:]]*true' <<<"$runs"
}
# The smoke test step: every matrix entry runs it, and ubuntu-latest runs the full stack.
smokeStep() {
    jq -e --arg mode "\${{ matrix.runner == 'ubuntu-24.04-arm' && 'nodb' || 'full' }}" \
        '[.jobs.test.steps[] | select(.uses == "./.github/actions/smoke-test")]
        | length == 1 and .[0].with.template == "${{ matrix.template }}" and .[0].with.mode == $mode' "$tmp/workflow.json" >/dev/null
}
actionRuns() {
    local want
    # shellcheck disable=SC2016 # the literal run strings of the action
    want='["\"$GITHUB_ACTION_PATH/build.sh\" \"$TEMPLATE\"","\"$GITHUB_ACTION_PATH/test.sh\" \"$TEMPLATE\""]'
    [ "$(jq -c '[.runs.steps[].run]' "$tmp/action.json")" = "$want" ] || return 1
    jq -e '.runs.steps | all(.env.MODE == "${{ inputs.mode }}" and .env.TEMPLATE == "${{ inputs.template }}")' "$tmp/action.json" >/dev/null || return 1
    jq -e '.inputs.mode.default == "full"' "$tmp/action.json" >/dev/null
}
# The Pick step, executed: a pull request picks the changed templates; schedule and dispatch pick all four.
pick() { # EVENT CHANGES -> templates JSON
    local out="$tmp/pick-output"
    : >"$out"
    EVENT=$1 CHANGES=$2 GITHUB_OUTPUT=$out bash -euo pipefail -c "$(jq -r '.jobs["detect-changes"].steps[] | select(.id == "pick") | .run' "$tmp/workflow.json")"
    sed -n 's/^templates=//p' "$out"
}
pickStep() {
    local all='["dotnet","dotnet-aspire","javascript-node","python"]'
    [ "$(pick pull_request '["python","shared"]')" = '["python"]' ] &&
        [ "$(pick pull_request '["dotnet","dotnet-aspire","javascript-node","python","shared"]')" = "$all" ] &&
        [ "$(pick pull_request '[]')" = '[]' ] &&
        [ "$(pick schedule '')" = "$all" ] &&
        [ "$(pick workflow_dispatch '')" = "$all" ] &&
        jq -e '.jobs.test.strategy.matrix.template == "${{ fromJSON(needs.detect-changes.outputs.templates) }}"' "$tmp/workflow.json" >/dev/null
}
# The static job runs every gate that needs no Docker.
staticJob() {
    local runs
    runs=$(jq -r '.jobs.static.steps[].run // empty' "$tmp/workflow.json")
    for gate in "shellcheck -x -P SCRIPTDIR" test/test-utils/check-shared.sh test/test-utils/check-forbidden.sh test/test-utils/check-static.sh test/test-utils/check-tags.sh; do
        grep -qF -- "$gate" <<<"$runs" || { echo "static job does not run $gate" >&2; return 1; }
    done
}
# filterSelects FILTERS-JSON PATH: the templates the paths filter selects for a change to PATH (bash patterns).
filterSelects() {
    jq -r 'to_entries[] | select(.key != "shared") | .key as $k | .value | flatten[] | "\($k)\t\(.)"' "$1" |
        while IFS="$(printf '\t')" read -r key pattern; do
            # shellcheck disable=SC2053 # the pattern is meant to glob
            if [[ $2 == $pattern ]]; then echo "$key"; fi
        done | sort -u | paste -sd' ' -
}
# checkFilters FILTERS-JSON: a template's own files select it, the shared test files select all four, and other
# files select nothing (13 representative paths).
checkFilters() {
    local path want got all="dotnet dotnet-aspire javascript-node python"
    while IFS='=' read -r path want; do
        got=$(filterSelects "$1" "$path")
        if [ "$got" != "$want" ]; then echo "a change to $path selects '$got', want '$want'" >&2; return 1; fi
    done <<PATHS
src/dotnet/.devcontainer/devcontainer.json=dotnet
src/dotnet-aspire/.devcontainer/devcontainer.json=dotnet-aspire
src/javascript-node/.devcontainer/devcontainer.json=javascript-node
src/python/.devcontainer/devcontainer.json=python
test/dotnet/test.sh=dotnet dotnet-aspire
test/javascript-node/index.js=javascript-node
test/python/test.sh=python
test/test-utils/test-utils.sh=$all
test/fixtures/azure-incompatible/documents.sql=$all
.github/actions/smoke-test/build.sh=$all
.github/workflows/test-pr.yaml=$all
README.md=
docs/images/x.png=
PATHS
}
pathsFilter() {
    jq -r '.jobs["detect-changes"].steps[] | select(.id == "filter") | .with.filters' "$tmp/workflow.json" >"$tmp/filters.yml"
    yaml2json "$tmp/filters.yml" >"$tmp/filters.json"
    checkFilters "$tmp/filters.json"
}
# A mirror download reaches pip only after its hashes are checked against pypi.org.
wheelsVerified() { grep -qF 'python /smoke/verify_wheels.py /smoke/wheels' .github/actions/smoke-test/build.sh; }

expect "S15 actions pinned by commit SHA" pinned
expect "S15 triggers (PR, weekly, manual), permissions, amd64 and arm64 runners" triggers
expect "S15 only the two known job and step conditions" conditions
expect "S15 no continue-on-error" noContinueOnError
expect "S15 no step swallows a failure" noSwallowedFailures
expect "S15 every matrix entry runs the smoke test; ubuntu-latest runs the full stack" smokeStep
expect "S15 the smoke-test action runs build.sh and test.sh as they are" actionRuns
expect "S15 the Pick step selects the changed templates, and all four on schedule and dispatch" pickStep
expect "S15 the static job runs shellcheck, check-shared, check-forbidden, check-static, check-tags" staticJob
expect "S15 paths filter: own, shared, and unrelated files (13 paths)" pathsFilter
expect "mirror wheels are verified before pip may use them" wheelsVerified

echo "check-static: $failures failure(s)"
[ "$failures" -eq 0 ]
