#!/usr/bin/env bash
# The whole local gauntlet in one command: static gates, negative controls for the home-grown
# checks, the template matrix on Docker, mutation testing, and supply-chain checks. Each layer is
# recorded only after it passes; success requires every layer in EXPECTED.
#
# Usage: test/gauntlet.sh
# Needs: Docker (one stack at a time, about 2 CPUs and 3 GB while a template is up), Node.js for
# npx, jq, git, ruby (YAML), shellcheck, curl. Runs on macOS (bash 3.2) and Linux.
# Environment: the SMOKE_* variables of .github/actions/smoke-test/build.sh and test.sh, for
# networks that block public package registries; GAUNTLET_OUT (default: $TMPDIR/azsqldc-gauntlet);
# GAUNTLET_BASE (default: main), the commit the branch is compared against.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
OUT=${GAUNTLET_OUT:-${TMPDIR:-/tmp}/azsqldc-gauntlet}
BASE=${GAUNTLET_BASE:-main}
DEVCONTAINER=${DEVCONTAINER:-npx -y @devcontainers/cli@0.89.0}
TEMPLATES="dotnet dotnet-aspire javascript-node python"
EXPECTED="source-state lint static controls tags extensions s12 matrix mutation supply-chain cleanup"
PASSED=""
SMOKE=.github/actions/smoke-test

rm -rf "$OUT" # no layer may read a previous run's output
mkdir -p "$OUT"
docker images --format '{{.Repository}}:{{.Tag}}' | sort -u >"$OUT/images-before.txt"
exec > >(tee "$OUT/gauntlet.log") 2>&1
started=$(date +%s)

passed() { PASSED="$PASSED $1"; echo "=== layer $1: PASSED ($(($(date +%s) - started)) s elapsed)"; }
die() { echo "=== GAUNTLET FAILED: $*" >&2; exit 1; }
yaml2json() { ruby -ryaml -rjson -e 'puts JSON.generate(YAML.load_file(ARGV[0]))' "$1"; }

# expectFail LABEL NEEDLE CMD...: CMD must exit non-zero and print NEEDLE. A negative control.
expectFail() {
    local label=$1 needle=$2 out rc=0
    shift 2
    out=$("$@" 2>&1) || rc=$?
    if [ "$rc" -eq 0 ]; then die "control '$label' passed; the check cannot fail"; fi
    if ! grep -qF -- "$needle" <<<"$out"; then die "control '$label' failed for another reason (exit $rc): $(tail -n 5 <<<"$out")"; fi
    echo "control ok: $label (exit $rc, reported '$needle')"
}

# M9 on the commits after BASE in REPO: Carlos is the only author, no AI trailer or mention.
checkCommits() { # REPO BASE
    local log authors
    log=$(git -C "$1" log --format='%an <%ae>%n%B' "$2..HEAD")
    authors=$(git -C "$1" log --format='%an <%ae>' "$2..HEAD" | sort -u)
    [ -n "$authors" ] || { echo "no commits after $2" >&2; return 1; }
    if grep -inE 'co-authored-by|claude|anthropic|generated with' <<<"$log"; then echo "M9: AI trailer or mention in a commit" >&2; return 1; fi
    if [ "$authors" != "Carlos Robles <contact@croblesm.com>" ]; then echo "M9: other authors: $authors" >&2; return 1; fi
    echo "M9: $(git -C "$1" rev-list --count "$2..HEAD") commits after $2, all by $authors, no AI trailer"
}

# filterSelects FILTERS-JSON PATH: the templates the paths filter selects for a change to PATH
# (bash patterns: * also matches /, like the filter's ** here).
filterSelects() {
    jq -r 'to_entries[] | select(.key != "shared") | .key as $k | .value | flatten[] | "\($k)\t\(.)"' "$1" |
        while IFS="$(printf '\t')" read -r key pattern; do
            # shellcheck disable=SC2053 # the pattern is meant to glob
            if [[ $2 == $pattern ]]; then echo "$key"; fi
        done | sort -u | paste -sd' ' -
}

# checkFilters FILTERS-JSON: each template's own files select it, the shared test files select all four,
# and files outside the tests select nothing.
checkFilters() {
    local path want got all="dotnet dotnet-aspire javascript-node python"
    while IFS='=' read -r path want; do
        got=$(filterSelects "$1" "$path")
        if [ "$got" != "$want" ]; then echo "S15: a change to $path selects '$got', want '$want'" >&2; return 1; fi
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

layerSourceState() {
    if [ -n "$(git status --porcelain)" ]; then git status --short; die "the working tree has uncommitted or untracked files"; fi
    echo "source: $(git rev-parse HEAD) (tree $(git rev-parse 'HEAD^{tree}')) on $(git rev-parse --abbrev-ref HEAD)"
    echo "host: $(uname -srm); docker $(docker version --format '{{.Server.Version}} {{.Server.Os}}/{{.Server.Arch}}') ($(docker info --format '{{.Name}}, {{.NCPU}} CPUs, {{.MemTotal}} bytes'))"
    echo "tools: devcontainer $($DEVCONTAINER --version), $(shellcheck --version | sed -n 's/^version: /shellcheck /p'), $(jq --version), bash $BASH_VERSION, $(git --version), ruby $(ruby -e 'print RUBY_VERSION')"
    echo "network overrides: SMOKE_NUGET_SOURCE=${SMOKE_NUGET_SOURCE:-} SMOKE_PIP_MIRROR=${SMOKE_PIP_MIRROR:-} SMOKE_NO_NPM_REGISTRY=${SMOKE_NO_NPM_REGISTRY:-}"
}

layerLint() {
    local files t
    files=$(git ls-files '*.sh')
    # shellcheck disable=SC2086 # file list without spaces
    shellcheck -x -P SCRIPTDIR $files
    echo "shellcheck: $(echo "$files" | wc -l | tr -d ' ') scripts, 0 findings"
    # devcontainer.json is JSONC; the Dev Container CLI reads those below.
    for f in $(git ls-files '*.json' ':!:*devcontainer.json'); do jq empty "$f"; done
    echo "json: $(git ls-files '*.json' ':!:*devcontainer.json' | wc -l | tr -d ' ') files parse"
    for f in $(git ls-files '*.yml' '*.yaml'); do yaml2json "$f" >/dev/null; done
    echo "yaml: $(git ls-files '*.yml' '*.yaml' | wc -l | tr -d ' ') files parse"
    for t in $TEMPLATES; do
        $DEVCONTAINER read-configuration --workspace-folder "src/$t" >"$OUT/config-$t.json" 2>"$OUT/config-$t.err"
        jq -e .configuration "$OUT/config-$t.json" >/dev/null
    done
    echo "devcontainer.json: 4 files read by the Dev Container CLI"
}

layerStatic() {
    local t ids compose filters path want got
    test/test-utils/check-shared.sh
    test/test-utils/check-forbidden.sh

    ids=$(for t in src/*/devcontainer-template.json; do jq -r .id "$t"; done | sort | paste -sd' ' -)
    [ "$ids" = "dotnet dotnet-aspire javascript-node python" ] || die "M1: template ids are '$ids'"
    for t in $TEMPLATES; do [ "$(jq -r .id "src/$t/devcontainer-template.json")" = "$t" ] || die "M1: src/$t has another id"; done
    echo "M1: ids unchanged: $ids"

    for t in $TEMPLATES; do
        [ "$(grep -c '<DSP>Microsoft.Data.Tools.Schema.Sql.SqlAzureV12DatabaseSchemaProvider</DSP>' "src/$t/database/Library/Library.sqlproj")" = 1 ] || die "M2: src/$t DSP"
    done
    echo "M2: all 4 SQL projects target SqlAzureV12DatabaseSchemaProvider"

    # Source .sql only: the committed obj/ build outputs that this branch deletes held .sql copies too.
    git diff --quiet "$BASE" HEAD -- ':(glob)src/*/database/Library/**/*.sql' ':(exclude,glob)src/*/database/Library/obj/**' ':(exclude,glob)src/*/database/Library/bin/**' || die "M3: .sql files under database/Library changed since $BASE"
    [ "$(git ls-files ':(glob)src/*/database/Library/**/*.sql' | wc -l | tr -d ' ')" = 28 ] || die "M3: expected 28 .sql files"
    echo "M3: 28 .sql files under src/*/database/Library identical to $BASE"

    for t in $TEMPLATES; do
        jq -e '.configuration
            | (.forwardPorts | index(1433))
            and (.customizations.vscode.extensions | index("ms-mssql.mssql"))
            and any(.customizations.vscode.settings."mssql.connections"[]; .profileName == "LocalDev" and .server == "localhost,1433")' \
            "$OUT/config-$t.json" >/dev/null || die "M7: src/$t lost LocalDev, port 1433, or ms-mssql.mssql"
    done
    echo "M7: LocalDev profile, port 1433, and ms-mssql.mssql in all 4"

    for t in $TEMPLATES; do
        compose=$(yaml2json "src/$t/.devcontainer/docker-compose.yml")
        jq -e '(has("version") | not)
            and .services.db.image == "mcr.microsoft.com/mssql/server:2025-latest"
            and .services.db.platform == "linux/amd64"
            and .services.db.environment.MSSQL_PID == "EnterpriseDeveloper"
            and (.services.db.healthcheck.test | tostring | contains("/opt/mssql-tools18/bin/sqlcmd"))
            and .services.db.deploy.resources.limits == {"cpus": "2", "memory": "2048M"}
            and (.services.db | has("container_name") | not)
            and .services.app.depends_on.db.condition == "service_healthy"
            and .services.app.network_mode == "service:db"' <<<"$compose" >/dev/null || die "F3/F7/N1: src/$t docker-compose.yml"
    done
    echo "F3/F7/N1: all 4 compose files: SQL Server 2025 Enterprise Developer, amd64, healthcheck, 2 CPU/2048M, app waits for healthy"

    [ "$(git ls-files '.github/**' | xargs grep -hE '^\s*-?\s*uses:' | grep -vcE 'uses: (\./|[^@]+@[0-9a-f]{40}( |$))')" = 0 ] || die "S15: an action is not pinned by SHA"
    yaml2json .github/workflows/test-pr.yaml >"$OUT/test-pr.json"
    jq -e '(.true | has("pull_request") and has("schedule") and has("workflow_dispatch"))
        and (.jobs.test.strategy.matrix.runner == ["ubuntu-latest", "ubuntu-24.04-arm"])' "$OUT/test-pr.json" >/dev/null || die "S15: triggers or runners"
    # S15: simulate the paths filter on 13 representative paths.
    filters=$(jq -r '.jobs["detect-changes"].steps[] | select(.id == "filter") | .with.filters' "$OUT/test-pr.json")
    printf '%s\n' "$filters" >"$OUT/filters.yml"
    yaml2json "$OUT/filters.yml" >"$OUT/filters.json"
    checkFilters "$OUT/filters.json" || die "S15: paths filter"
    jq -e '.permissions["pull-requests"] == "read"' "$OUT/test-pr.json" >/dev/null || die "S15: paths-filter needs pull-requests: read"
    echo "S15: paths filter: src/<id> and test/<id> select their templates, shared test files select all 4, other files none (13 paths); pull-requests: read; actions SHA-pinned; amd64 + arm64 runners; PR, weekly, and manual triggers"

    git ls-files | grep -E '(^|/)(CLAUDE|AGENTS|SPEC|EVIDENCE)\.md$|(^|/)\.claude/' && die "M9: an AI file is tracked"
    checkCommits "$ROOT" "$BASE"
}

layerControls() {
    local tmp
    tmp=$(mktemp -d "$OUT/controls.XXXX")

    cp -R src "$tmp/src"
    echo "# drift" >>"$tmp/src/python/.devcontainer/sql/postCreateCommand.sh"
    expectFail "check-shared sees one changed byte" "DIFFERS: python/.devcontainer/sql/postCreateCommand.sh" test/test-utils/check-shared.sh "$tmp/src"

    plant() { # LABEL NEEDLE SHELL-SNIPPET: plant a violation in a fresh clone, commit it, run check-forbidden
        rm -rf "$tmp/repo"
        git clone -q "$ROOT" "$tmp/repo"
        (cd "$tmp/repo" && eval "$3" && git add -Af . && git -c user.name=control -c user.email=control@localhost commit -qm control)
        expectFail "$1" "$2" test/test-utils/check-forbidden.sh "$tmp/repo"
    }
    # The planted strings are split ('' joins them in the shell) so this file doesn't trip the gates.
    plant "check-forbidden: gated registry" "FORBIDDEN: S14/M4 no gated registry reference" "echo '# x.azure''cr.io/y' >>src/python/.devcontainer/docker-compose.yml"
    plant "check-forbidden: registry credential" "FORBIDDEN: M4 no registry credentials" "echo 'ACR_CONTAINER_REGISTRY_''PASSWORD=x' >>src/python/.devcontainer/.env"
    plant "check-forbidden: build output" "FORBIDDEN: M5 no bin/ or obj/ tracked anywhere" "mkdir -p src/python/database/Library/bin && echo x >src/python/database/Library/bin/x.txt"
    plant "check-forbidden: binary file" "FORBIDDEN: M5 no binary files under src/" "printf 'a\\000b' >src/python/blob.dat"
    plant "check-forbidden: global prune" "FORBIDDEN: M6 no global destructive docker command" "echo 'docker system'' prune -af' >>test/python/test.sh"
    plant "check-forbidden: script without pipefail" "FORBIDDEN: M8 every script starts with set -euo pipefail" "printf '#!/bin/sh\\necho hi\\n' >test/unsafe.sh"
    # The round 1 verifier's spellings (F8): each must fail too.
    plant "check-forbidden: uppercase registry host" "FORBIDDEN: S14/M4 no gated registry reference" "echo '# SQLDBPREVIEW.AZURE''CR.IO/azure-sql/db-dev' >>src/python/.devcontainer/docker-compose.yml"
    plant "check-forbidden: REGISTRY_PASSWORD" "FORBIDDEN: M4 no registry credentials" "echo 'REGISTRY_''PASSWORD=x' >>src/python/.devcontainer/.env"
    plant "check-forbidden: docker login with two spaces" "FORBIDDEN: M4 no registry credentials" "echo 'docker  lo''gin example.io' >>test/python/test.sh"
    plant "check-forbidden: volume rm fed by docker volume ls" "FORBIDDEN: M6 no global destructive docker command" "echo 'docker volume r''m \$(docker volume ls -q)' >>test/python/test.sh"
    plant "check-forbidden: rm fed by docker ps" "FORBIDDEN: M6 no global destructive docker command" "echo 'docker r''m -f \$(docker ps -aq)' >>test/python/test.sh"
    plant "check-forbidden: xargs docker rm" "FORBIDDEN: M6 no global destructive docker command" "echo 'docker ps -aq | xargs docker r''m -f' >>test/python/test.sh"
    plant "check-forbidden: pipefail only inside a function" "FORBIDDEN: M8 every script starts with set -euo pipefail" "printf '#!/bin/sh\\nf() {\\nset -euo pipefail\\n}\\necho hi\\n' >test/unsafe.sh"
    plant "check-forbidden: continue-on-error" "FORBIDDEN: S15 no continue-on-error in workflows" "echo '    continue-on-error: true' >>.github/workflows/test-pr.yaml"

    mkdir -p "$tmp/tags/dotnet/.devcontainer"
    cp src/dotnet/.devcontainer/Dockerfile "$tmp/tags/dotnet/.devcontainer/"
    jq '.options.imageVariant.proposals += ["10.0-nosuchdistro"]' src/dotnet/devcontainer-template.json >"$tmp/tags/dotnet/devcontainer-template.json"
    expectFail "check-tags: a proposal that doesn't exist" "MISSING: devcontainers/dotnet:2-10.0-nosuchdistro" test/test-utils/check-tags.sh "$tmp/tags"
    # A real tag with no arm64 image (F7): pins the arm64 half of the check.
    mkdir -p "$tmp/tags2/universal/.devcontainer"
    # shellcheck disable=SC2016 # a literal ${templateOption:imageVariant}
    printf 'FROM mcr.microsoft.com/devcontainers/universal:${templateOption:imageVariant}\n' >"$tmp/tags2/universal/.devcontainer/Dockerfile"
    echo '{"id": "universal", "options": {"imageVariant": {"proposals": ["2"], "default": "2"}}}' >"$tmp/tags2/universal/devcontainer-template.json"
    expectFail "check-tags: a real tag with amd64 only" "MISSING: devcontainers/universal:2 [amd64]" test/test-utils/check-tags.sh "$tmp/tags2"

    jq '.python |= map(select(type != "array" and . != "test/python/**"))' "$OUT/filters.json" >"$tmp/filters-mutant.json"
    expectFail "S15 filter check: python loses its test and shared paths" "S15: a change to test/python/test.sh selects ''" checkFilters "$tmp/filters-mutant.json"

    rm -rf "$tmp/repo"
    git clone -q "$ROOT" "$tmp/repo"
    git -C "$tmp/repo" -c user.name=Someone -c user.email=someone@localhost commit -q --allow-empty -m "x" -m "Co-Authored-By: Someone <someone@localhost>"
    expectFail "M9 commit check: trailer and author" "M9: AI trailer or mention" checkCommits "$tmp/repo" "$(git rev-parse "$BASE")"

    rm -rf "$tmp"
}

# checkExtensionIds MANIFEST ID...: every id is on the Marketplace and not deprecated in VS Code's own
# extension control manifest (the list VS Code uses to mark extensions deprecated).
checkExtensionIds() {
    local manifest=$1 id bad=0 found
    shift
    jq -e '.deprecated | length > 0' "$manifest" >/dev/null || { echo "BROKEN: no deprecated list in $manifest" >&2; return 2; }
    for id in "$@"; do
        if jq -e --arg id "$id" '.deprecated[$id]' "$manifest" >/dev/null; then echo "DEPRECATED: $id" >&2; bad=1; continue; fi
        found=$(curl -fsS -m 30 -H 'Content-Type: application/json' -H 'Accept: application/json;api-version=7.2-preview.1' \
            -d "{\"filters\":[{\"criteria\":[{\"filterType\":7,\"value\":\"$id\"}]}],\"flags\":0}" \
            https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery |
            jq -r --arg id "$id" '[.results[0].extensions[]? | "\(.publisher.publisherName).\(.extensionName)" | ascii_downcase] | index($id | ascii_downcase) != null')
        if [ "$found" != true ]; then echo "NOT ON MARKETPLACE: $id" >&2; bad=1; fi
    done
    return "$bad"
}

layerExtensions() {
    local manifest="$OUT/vscode-extension-control-manifest.json" ids
    curl -fsS -m 60 https://main.vscode-cdn.net/extensions/marketplace.json -o "$manifest"
    ids=$(jq -r '.configuration.customizations.vscode.extensions[]' "$OUT"/config-*.json | sort -u)
    # shellcheck disable=SC2086 # ids is a word list
    checkExtensionIds "$manifest" $ids || die "extensions: an id is deprecated or missing"
    echo "extensions: $(echo "$ids" | wc -l | tr -d ' ') ids in the 4 templates are on the Marketplace and none is deprecated"
    expectFail "extension check: a deprecated id" "DEPRECATED: eg2.vscode-npm-script" checkExtensionIds "$manifest" ms-mssql.mssql eg2.vscode-npm-script
    expectFail "extension check: an id not on the Marketplace" "NOT ON MARKETPLACE: ms-mssql.no-such-extension" checkExtensionIds "$manifest" ms-mssql.no-such-extension
}

# Removes the images this run pulled that the templates don't use (for example the engine mutant's
# SQL Server 2022). Images present before the run and the templates' own images stay.
layerCleanup() {
    local keep image from removed=""
    keep=$( (echo mcr.microsoft.com/mssql/server:2025-latest
        for t in $TEMPLATES; do
            # shellcheck disable=SC2016 # a literal ${templateOption:imageVariant}
            from=$(sed -n 's#^FROM \(.*\)\${templateOption:imageVariant}$#\1#p' "src/$t/.devcontainer/Dockerfile")
            jq -r --arg from "$from" '.options.imageVariant.proposals[] | $from + .' "src/$t/devcontainer-template.json"
        done) | sort -u)
    for image in $(docker images --format '{{.Repository}}:{{.Tag}}' | sort -u | comm -23 - "$OUT/images-before.txt" | comm -23 - <(echo "$keep")); do
        case $image in
            mcr.microsoft.com/*) docker image rm "$image" >/dev/null; removed="$removed $image" ;;
            *) die "cleanup: unexpected new image $image" ;;
        esac
    done
    echo "cleanup: removed${removed:- nothing}; kept the templates' images: $(echo "$keep" | paste -sd' ' -)"
}

layerS12() {
    local tmp out rc=0 image=azsqldc-s12:local
    tmp=$(mktemp -d "$OUT/s12.XXXX")
    cp -R src/dotnet/.devcontainer/. "$tmp/"
    perl -pi -e 's/\$\{templateOption:imageVariant\}/10.0-noble/' "$tmp/Dockerfile"
    docker build --no-cache --label azsqldc.s12=1 -t "$image" "$tmp" >"$OUT/s12-good.log" 2>&1 || die "S12 control: the unmodified Dockerfile doesn't build (see $OUT/s12-good.log)"
    docker run --rm "$image" sqlcmd --version | grep -q 'v1.10.0' || die "S12 control: sqlcmd v1.10.0 missing from the unmodified build"
    docker image rm "$image" >/dev/null
    echo "S12 control: the unmodified Dockerfile builds and has sqlcmd v1.10.0"
    perl -pi -e '$n += s/(sha256=)([0-9a-f])/$1 . ($2 eq "0" ? "1" : "0")/e; END { exit($n == 2 ? 0 : 1) }' "$tmp/sql/installSQLtools.sh"
    out=$(docker build --no-cache --label azsqldc.s12=1 -t "$image" "$tmp" 2>&1) || rc=$?
    echo "$out" >"$OUT/s12-bad.log"
    [ "$rc" -ne 0 ] || die "S12: the build passed with a wrong sqlcmd checksum"
    grep -q 'FAILED' <<<"$out" || die "S12: the build failed, but not at the checksum (see $OUT/s12-bad.log)"
    if docker image inspect "$image" >/dev/null 2>&1; then die "S12: an image was produced"; fi
    echo "S12: with a wrong checksum the image build fails (exit $rc): $(grep -m1 -o 'sha256sum: WARNING.*' <<<"$out")"
    rm -rf "$tmp"
}

# runSmoke NAME TEMPLATE [VAR=VALUE...]: build.sh + test.sh in one environment; appends to matrix.tsv.
runSmoke() {
    local name=$1 template=$2 start rc=0 log="$OUT/matrix-$1.log"
    shift 2
    start=$(date +%s)
    env RUN_TAG=g WORK_ROOT="$OUT/ws" "$@" bash -c "$SMOKE/build.sh $template && $SMOKE/test.sh $template" >"$log" 2>&1 || rc=$?
    printf '%s\t%s\t%s\t%s\t%s s\t%s passed, %s failed, %s skipped\n' "$name" "$template" "$*" \
        "$([ "$rc" -eq 0 ] && echo PASS || echo "FAIL($rc)")" "$(($(date +%s) - start))" \
        "$(grep -c '^PASS: ' "$log")" "$(grep -c '^FAIL: ' "$log")" "$(grep -c '^SKIP: ' "$log")" | tee -a "$OUT/matrix.tsv"
    return "$rc"
}

layerMatrix() {
    local t failed=0 arch
    arch=linux/$(docker version --format '{{.Server.Arch}}')
    mkdir -p "$OUT/ws"
    for t in $TEMPLATES; do runSmoke "S1-$t" "$t" PLATFORM="$arch" || failed=$((failed + 1)); done
    for t in $TEMPLATES; do runSmoke "S2-$t-amd64" "$t" PLATFORM=linux/amd64 || failed=$((failed + 1)); done
    runSmoke S3-dotnet-8.0 dotnet PLATFORM="$arch" IMAGE_VARIANT=8.0-noble || failed=$((failed + 1))
    runSmoke S3-python-3.13 python PLATFORM="$arch" IMAGE_VARIANT=3.13-trixie || failed=$((failed + 1))
    runSmoke S3-javascript-node-22 javascript-node PLATFORM="$arch" IMAGE_VARIANT=22-trixie || failed=$((failed + 1))
    for t in $TEMPLATES; do runSmoke "CI-arm64-nodb-$t" "$t" PLATFORM="$arch" MODE=nodb || failed=$((failed + 1)); done
    leftovers
    [ "$failed" -eq 0 ] || die "matrix: $failed run(s) failed (logs in $OUT)"
}

leftovers() { # every stack this gauntlet started must be gone
    local left
    left=$(docker ps -a --format '{{.Label "com.docker.compose.project"}} {{.Names}}' | awk '/^azsqldc-/')
    [ -z "$left" ] || die "containers left behind: $left"
    echo "teardown: no azsqldc-* containers left"
}

layerMutation() {
    MUTANTS_OUT="$OUT/mutants" test/mutants.sh
    leftovers
}

layerSupplyChain() {
    local arch want got
    for arch in amd64 arm64; do
        want=$(sed -n "s/^ *$arch) sha256=\([0-9a-f]*\).*/\1/p" src/dotnet/.devcontainer/sql/installSQLtools.sh)
        got=$(curl -fsSL "https://github.com/microsoft/go-sqlcmd/releases/download/v1.10.0/sqlcmd-linux-$arch.tar.bz2" | shasum -a 256 | cut -d' ' -f1)
        [ -n "$want" ] && [ "$want" = "$got" ] || die "supply chain: sqlcmd $arch pinned $want, release has $got"
        echo "sqlcmd v1.10.0 $arch: pinned SHA-256 matches the release asset ($got)"
    done
    # Known vulnerabilities in the pinned direct dependencies, from the OSV database (covers GitHub advisories).
    jq -n '{queries: [
        {package: {ecosystem: "PyPI", name: "mssql-python"}, version: "1.14.0"},
        {package: {ecosystem: "npm", name: "mssql"}, version: "12.7.2"},
        {package: {ecosystem: "NuGet", name: "Microsoft.Data.SqlClient"}, version: "6.1.7"},
        {package: {ecosystem: "NuGet", name: "Microsoft.SqlPackage"}, version: "170.5.76"},
        {package: {ecosystem: "NuGet", name: "Microsoft.Build.Sql"}, version: "2.2.0"},
        {package: {ecosystem: "NuGet", name: "Aspire.Cli"}, version: "13.5.3"},
        {package: {ecosystem: "Go", name: "github.com/microsoft/go-sqlcmd"}, version: "1.10.0"}]}' >"$OUT/osv-query.json"
    curl -fsS -m 60 -H 'Content-Type: application/json' -d @"$OUT/osv-query.json" https://api.osv.dev/v1/querybatch >"$OUT/osv-result.json"
    [ "$(jq '.results | length' "$OUT/osv-result.json")" = 7 ] || die "supply chain: unexpected OSV answer"
    if jq -e '[.results[].vulns // empty] | flatten | length > 0' "$OUT/osv-result.json" >/dev/null; then
        jq -c '.results' "$OUT/osv-result.json"
        die "supply chain: OSV lists vulnerabilities for a pinned dependency"
    fi
    echo "OSV: 0 known vulnerabilities in 7 pinned direct dependencies"
    # Secrets: nothing but the documented local-dev password, no keys or tokens.
    local rc=0 hits
    hits=$(git grep -nIE -e '-----BEGIN [A-Z ]*PRIVATE KEY' -e 'AKIA[0-9A-Z]{16}' -e 'gh[pousr]_[A-Za-z0-9]{36}' -e 'AccountKey=' -e 'xox[baprs]-' -- . ':!test/gauntlet.sh') || rc=$?
    case $rc in
        1) ;;
        0) die "supply chain: a secret-like string is tracked: $hits" ;;
        *) die "supply chain: the secret scan broke (git grep exit $rc)" ;;
    esac
    [ "$(git grep -lI 'P@ss''w0rd!' | paste -sd' ' -)" = "src/dotnet-aspire/.devcontainer/.env src/dotnet/.devcontainer/.env src/javascript-node/.devcontainer/.env src/python/.devcontainer/.env" ] ||
        die "supply chain: the dev password appears outside the four .env files: $(git grep -lI 'P@ss''w0rd!')"
    echo "secrets: no key or token patterns; the dev password is only in the four .env files"
}

# Plain calls, not "layer && passed": set -e is suspended inside a function called from && or if.
layerSourceState; passed source-state
layerLint; passed lint
layerStatic; passed static
layerControls; passed controls
test/test-utils/check-tags.sh; passed tags
layerExtensions; passed extensions
layerS12; passed s12
layerMatrix; passed matrix
layerMutation; passed mutation
layerSupplyChain; passed supply-chain
layerCleanup; passed cleanup

[ "$(git status --porcelain)" = "" ] || die "the run changed the working tree"
[ "$PASSED" = " $EXPECTED" ] || die "layers passed: '$PASSED', expected: '$EXPECTED'"
echo "=== GAUNTLET PASSED: $EXPECTED ($(($(date +%s) - started)) s) at $(git rev-parse HEAD); logs in $OUT"
