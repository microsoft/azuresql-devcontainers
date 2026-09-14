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
    test/test-utils/check-shared.sh
    test/test-utils/check-forbidden.sh
    test/test-utils/check-static.sh
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
    plant "check-forbidden: gated registry" "FORBIDDEN: S14/M4 no gated registry reference" "echo '# example-gated.azure''cr.io/sample/image:1' >>src/python/.devcontainer/docker-compose.yml"
    plant "check-forbidden: registry credential" "FORBIDDEN: M4 no registry credentials" "echo 'ACR_CONTAINER_REGISTRY_''PASSWORD=x' >>src/python/.devcontainer/.env"
    plant "check-forbidden: build output" "FORBIDDEN: M5 no bin/ or obj/ tracked anywhere" "mkdir -p src/python/database/Library/bin && echo x >src/python/database/Library/bin/x.txt"
    plant "check-forbidden: binary file" "FORBIDDEN: M5 no binary files under src/" "printf 'a\\000b' >src/python/blob.dat"
    plant "check-forbidden: global prune" "FORBIDDEN: M6 no global destructive docker command" "echo 'docker system'' prune -af' >>test/python/test.sh"
    plant "check-forbidden: script without pipefail" "FORBIDDEN: M8 every script starts with set -euo pipefail" "printf '#!/bin/sh\\necho hi\\n' >test/unsafe.sh"
    # The round 1 verifier's spellings (F8): each must fail too.
    plant "check-forbidden: uppercase registry host" "FORBIDDEN: S14/M4 no gated registry reference" "echo '# EXAMPLE-GATED.AZURE''CR.IO/SAMPLE/IMAGE:1' >>src/python/.devcontainer/docker-compose.yml"
    plant "check-forbidden: a registry password variable" "FORBIDDEN: M4 no registry credentials" "echo 'REGISTRY_''PASSWORD=x' >>src/python/.devcontainer/.env"
    plant "check-forbidden: a registry login with two spaces" "FORBIDDEN: M4 no registry credentials" "echo 'docker  lo''gin example.io' >>test/python/test.sh"
    plant "check-forbidden: volume rm fed by docker volume ls" "FORBIDDEN: M6 no global destructive docker command" "echo 'docker volume r''m \$(docker volume l''s -q)' >>test/python/test.sh"
    plant "check-forbidden: rm fed by docker ps" "FORBIDDEN: M6 no global destructive docker command" "echo 'docker r''m -f \$(docker p''s -aq)' >>test/python/test.sh"
    plant "check-forbidden: removal through xargs" "FORBIDDEN: M6 no global destructive docker command" "echo 'docker ps -aq | xargs docker r''m -f' >>test/python/test.sh"
    # The round 2 verifier's spellings (B5, B4).
    plant "check-forbidden: an ACR login command" "FORBIDDEN: M4 no registry credentials" "echo 'az acr lo''gin --name example' >>test/python/test.sh"
    plant "check-forbidden: an ACR password variable" "FORBIDDEN: M4 no registry credentials" "echo 'ACR''_PWD=x' >>src/python/.devcontainer/.env"
    plant "check-forbidden: a short registry password variable" "FORBIDDEN: M4 no registry credentials" "echo 'REGISTRY''_PASS=x' >>src/python/.devcontainer/.env"
    plant "check-forbidden: a login through podman" "FORBIDDEN: M4 no registry credentials" "echo 'podman lo''gin example.invalid -u x -p y' >>test/python/test.sh"
    plant "check-forbidden: for loop over an unfiltered listing" "FORBIDDEN: M6 no global destructive docker command" "echo 'for id in \$(docker p''s -aq); do docker r''m -f \"\$id\"; done' >>test/python/test.sh"
    plant "check-forbidden: backtick listing" "FORBIDDEN: M6 no global destructive docker command" "echo 'docker r''m -f \`docker p''s -aq\`' >>test/python/test.sh"
    plant "check-forbidden: line-continued prune" "FORBIDDEN: M6 no global destructive docker command" "printf 'docker system \\\\\\n  prune -af\\n' >>test/python/test.sh"
    plant "check-forbidden: set +e after the first line" "FORBIDDEN: M8 no script turns errexit off" "printf 'se''t +e\\n' >>test/python/test.sh"
    plant "check-forbidden: non-ASCII dll name" "FORBIDDEN: M5 no build outputs or images under src/" "echo x >src/python/caf$(printf '\\303\\251').dll"
    plant "check-forbidden: Dockerfile swallows the install" "FORBIDDEN: S12 no Dockerfile swallows a failed step" "perl -pi -e 's#RUN bash /tmp/installSQLtools.sh && rm /tmp/installSQLtools.sh#RUN bash /tmp/installSQLtools.sh |''| true; rm -f /tmp/installSQLtools.sh#' src/python/.devcontainer/Dockerfile"
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


    staticControl() { # LABEL NEEDLE SHELL-SNIPPET: mutate a fresh clone, run check-static
        rm -rf "$tmp/repo"
        git clone -q "$ROOT" "$tmp/repo"
        (cd "$tmp/repo" && eval "$3")
        expectFail "$1" "$2" test/test-utils/check-static.sh "$tmp/repo"
    }
    staticControl "check-static: test step failure swallowed" "FAILED: S15 no step swallows a failure" \
        "perl -pi -e 's#(run: .\"\\\$GITHUB_ACTION_PATH/test.sh\" \"\\\$TEMPLATE\")#\$1 |''| true#' .github/actions/smoke-test/action.yaml"
    staticControl "check-static: both runners in nodb mode" "FAILED: S15 every matrix entry runs the smoke test" \
        "perl -pi -e 's#mode: \\\$\\{\\{ matrix.runner.*#mode: nodb#' .github/workflows/test-pr.yaml"
    staticControl "check-static: test job disabled" "FAILED: S15 only the two known job and step conditions" \
        "perl -pi -e 's#if: needs.detect-changes.outputs.templates != .\\[\\].#if: false#' .github/workflows/test-pr.yaml"
    staticControl "check-static: Pick step selects nothing" "FAILED: S15 the Pick step selects" \
        "perl -pi -e 's#map\\(select\\(\\. != \"shared\"\\)\\)#map(select(. == \"none\"))#' .github/workflows/test-pr.yaml"
    staticControl "check-static: check-forbidden failure swallowed" "FAILED: S15 no step swallows a failure" \
        "perl -pi -e 's#run: test/test-utils/check-forbidden.sh#run: test/test-utils/check-forbidden.sh |''| true#' .github/workflows/test-pr.yaml"
    staticControl "check-static: python loses its test and shared filter entries" "FAILED: S15 paths filter" \
        "perl -0pi -e 's#(            python:\\n)              - \\*shared\\n(              - .src/python/\\*\\*.\\n)              - .test/python/\\*\\*.\\n#\$1\$2#' .github/workflows/test-pr.yaml"
    staticControl "check-static: a template id renamed" "FAILED: M1 template ids" \
        "perl -pi -e 's#\"id\": \"python\"#\"id\": \"python-sql\"#' src/python/devcontainer-template.json"
    staticControl "check-static: a seed row changed" "FAILED: M3 the 28 Library .sql files" \
        "perl -pi -e 's#Foundation and Earth#Foundation and Mars#' src/python/database/Library/postDeployment.sql"
    staticControl "check-static: port 1433 dropped" "FAILED: M7/S18 python" \
        "perl -pi -e 's#\\[5000, 1433\\]#[5000]#' src/python/.devcontainer/devcontainer.json"

    # The mirror gate (D2): a wheel whose bytes don't match pypi.org's digest is refused.
    mkdir -p "$tmp/wheels"
    echo tampered >"$tmp/wheels/mssql_python-1.14.0-cp314-cp314-manylinux_2_28_aarch64.whl"
    expectFail "verify_wheels.py: a tampered wheel" "MISMATCH mssql_python-1.14.0-cp314-cp314-manylinux_2_28_aarch64.whl" python3 test/python/verify_wheels.py "$tmp/wheels"

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
        # Extension ids are case-insensitive; the manifest's keys use the publisher's casing.
        if jq -e --arg id "$id" '[.deprecated | keys[] | ascii_downcase] | index($id | ascii_downcase) != null' "$manifest" >/dev/null; then
            echo "DEPRECATED: $id" >&2
            bad=1
            continue
        fi
        found=$(curl -fsS -m 30 -H 'Content-Type: application/json' -H 'Accept: application/json;api-version=7.2-preview.1' \
            -d "{\"filters\":[{\"criteria\":[{\"filterType\":7,\"value\":\"$id\"}]}],\"flags\":0}" \
            https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery |
            jq -r --arg id "$id" '[.results[0].extensions[]? | "\(.publisher.publisherName).\(.extensionName)" | ascii_downcase] | index($id | ascii_downcase) != null')
        if [ "$found" != true ]; then echo "NOT ON MARKETPLACE: $id" >&2; bad=1; fi
    done
    return "$bad"
}

# The VS Code server a dev container downloads, cached between runs (about 200 MB).
vscodeServer() {
    local cache=${GAUNTLET_CACHE:-$HOME/.cache/azsqldc-gauntlet} arch
    arch=$(docker version --format '{{.Server.Arch}}')
    case $arch in
        amd64) arch=x64 ;;
        arm64) arch=arm64 ;;
        *) die "no VS Code server build for $arch" ;;
    esac
    if [ ! -x "$cache/vscode-server-$arch/bin/code-server" ]; then
        mkdir -p "$cache/vscode-server-$arch"
        curl -fsSL -m 600 "https://update.code.visualstudio.com/latest/server-linux-$arch/stable" |
            tar -xz -C "$cache/vscode-server-$arch" --strip-components=1
    fi
    echo "$cache/vscode-server-$arch"
}

# checkExtensionInstalls ID...: a real VS Code server installs every id, the way a dev container does.
# One invocation per id (the CLI silently installs only the first of a long batch), each retried once so a
# transient gallery or node error is not a finding. An id the server refuses (one that ships built in, for
# example) fails both attempts, and a rolled-back install fails too: every id must be on disk afterwards.
checkExtensionInstalls() {
    local server out rc=0
    server=$(vscodeServer) || return 2
    out=$(docker run --rm --label azsqldc.extensions=1 -u vscode -v "$server:/vscode-server:ro" -e HOME=/tmp/home \
        mcr.microsoft.com/devcontainers/dotnet:2-10.0-noble \
        bash -c 'set -u; mkdir -p /tmp/home /tmp/ext; status=0
            for id in '"$*"'; do
                if ! /vscode-server/bin/code-server --install-extension "$id" --force --extensions-dir /tmp/ext >/tmp/install.log 2>&1 &&
                    ! /vscode-server/bin/code-server --install-extension "$id" --force --extensions-dir /tmp/ext >/tmp/install.log 2>&1; then
                    echo "REFUSED: $id: $(grep -iE "^Error|Failed Installing" /tmp/install.log | head -n 1)"
                    status=1
                fi
                ls /tmp/ext | grep -qi "^$id-" || { echo "NOT ON DISK: $id"; status=1; }
            done
            exit $status') || rc=$?
    if [ "$rc" -ne 0 ]; then printf '%s\n' "$out" | grep -E '^(REFUSED|NOT ON DISK)' >&2; fi
    return "$rc"
}

layerExtensions() {
    local manifest="$OUT/vscode-extension-control-manifest.json" ids
    curl -fsS -m 60 https://main.vscode-cdn.net/extensions/marketplace.json -o "$manifest"
    ids=$(jq -r '.configuration.customizations.vscode.extensions[]' "$OUT"/config-*.json | sort -u)
    # shellcheck disable=SC2086 # ids is a word list
    checkExtensionIds "$manifest" $ids || die "extensions: an id is deprecated or missing"
    echo "extensions: $(echo "$ids" | wc -l | tr -d ' ') ids in the 4 templates are on the Marketplace and none is deprecated"
    expectFail "extension check: a deprecated id" "DEPRECATED: eg2.vscode-npm-script" checkExtensionIds "$manifest" ms-mssql.mssql eg2.vscode-npm-script
    expectFail "extension check: a deprecated id in another case" "DEPRECATED: github.copilot-workspace" checkExtensionIds "$manifest" github.copilot-workspace
    expectFail "extension check: an id not on the Marketplace" "NOT ON MARKETPLACE: ms-mssql.no-such-extension" checkExtensionIds "$manifest" ms-mssql.no-such-extension

    # Installing them for real: the Marketplace answering is not the same as VS Code accepting the id.
    # shellcheck disable=SC2086 # ids is a word list
    checkExtensionInstalls $ids || die "extensions: a VS Code server refused an id, or its install was rolled back"
    echo "extensions: a VS Code server ($(basename "$(vscodeServer)")) installed all $(echo "$ids" | wc -l | tr -d ' ') ids"
    expectFail "extension install: an id that ships built in" "REFUSED: github.copilot-chat" checkExtensionInstalls github.copilot-chat
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

# s12Build TEMPLATE VARIANT: the template's .devcontainer builds, and with a wrong sqlcmd checksum it doesn't.
s12Build() {
    local tmp out rc=0 image="azsqldc-s12-$1:local"
    tmp=$(mktemp -d "$OUT/s12-$1.XXXX")
    cp -R "src/$1/.devcontainer/." "$tmp/"
    VARIANT=$2 perl -pi -e 's/\$\{templateOption:imageVariant\}/$ENV{VARIANT}/' "$tmp/Dockerfile"
    docker build --no-cache --label azsqldc.s12=1 -t "$image" "$tmp" >"$OUT/s12-$1-good.log" 2>&1 || die "S12 control: the unmodified $1 Dockerfile doesn't build (see $OUT/s12-$1-good.log)"
    docker run --rm "$image" sqlcmd --version | grep -q 'v1.10.0' || die "S12 control: sqlcmd v1.10.0 missing from the unmodified $1 build"
    docker image rm "$image" >/dev/null
    perl -pi -e '$n += s/(sha256=)([0-9a-f])/$1 . ($2 eq "0" ? "1" : "0")/e; END { exit($n == 2 ? 0 : 1) }' "$tmp/sql/installSQLtools.sh"
    out=$(docker build --no-cache --label azsqldc.s12=1 -t "$image" "$tmp" 2>&1) || rc=$?
    echo "$out" >"$OUT/s12-$1-bad.log"
    [ "$rc" -ne 0 ] || die "S12: the $1 build passed with a wrong sqlcmd checksum"
    grep -q 'FAILED' <<<"$out" || die "S12: the $1 build failed, but not at the checksum (see $OUT/s12-$1-bad.log)"
    if docker image inspect "$image" >/dev/null 2>&1; then die "S12: an image was produced for $1"; fi
    echo "S12 $1: unmodified builds with sqlcmd v1.10.0; with a wrong checksum the build fails (exit $rc): $(grep -m1 -o 'sha256sum: WARNING.*' <<<"$out")"
    rm -rf "$tmp"
}

layerS12() {
    s12Build dotnet 10.0-noble
    s12Build python 3.14-trixie
    s12Build javascript-node 24-trixie
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
        if [ -z "$want" ] || [ "$want" != "$got" ]; then
            die "supply chain: sqlcmd $arch pinned $want, release has $got"
        fi
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
