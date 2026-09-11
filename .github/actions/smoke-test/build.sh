#!/usr/bin/env bash
# Applies a template to a fresh workspace with its option values, adds the smoke test, and brings it up.
# Usage: build.sh <template-id>   (environment: see common.sh)
#
# Local-network escape hatches (unset in CI; never point at anything in committed files):
#   SMOKE_NUGET_SOURCE  a NuGet feed written to the workspace's NuGet.Config
#   SMOKE_PIP_MIRROR    a PyPI index to download the Python sample's wheels from; every wheel is
#                       checked against the SHA-256 that pypi.org publishes before pip may use it
set -euo pipefail
source "$(dirname "$0")/common.sh"
onExit() {
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "build.sh: failed (exit $rc). Last SQL Server log lines, then teardown:" >&2
        if [ -n "$PROJECT" ]; then docker compose -p "$PROJECT" logs --no-color --tail 15 db >&2 || echo "(no db logs)" >&2; fi
        teardown
    fi
}
trap onExit EXIT

teardown # leftovers from an earlier run of this exact configuration
if [ -n "$WS" ]; then rm -rf "$WS"; fi
useWorkspace "$BASE-$(date +%Y%m%d%H%M%S)"
mkdir -p "$WS"
echo "$WS" >"$POINTER"
echo "==> $TEMPLATE_ID ($IMAGE_VARIANT, $PLATFORM, $MODE) in $WS, compose project $PROJECT"
cp -R "$SRC_DIR/." "$WS/"

# Option substitution, as `devcontainer templates apply` does. That command only takes published
# OCI templates, so it can't test a branch. Text files only: grep -I skips binaries.
jq -e --arg v "$IMAGE_VARIANT" '.options.imageVariant.proposals | index($v)' "$SRC_DIR/devcontainer-template.json" >/dev/null
for key in $(jq -r '.options | keys[]' "$SRC_DIR/devcontainer-template.json"); do
    value=$(jq -r --arg k "$key" '.options[$k].default' "$SRC_DIR/devcontainer-template.json")
    if [ "$key" = imageVariant ]; then value=$IMAGE_VARIANT; fi
    grep -rlIF "\${templateOption:$key}" "$WS" | while IFS= read -r file; do
        KEY=$key VALUE=$value perl -pi -e 's/\$\{templateOption:\Q$ENV{KEY}\E\}/$ENV{VALUE}/g' "$file"
    done
done
# shellcheck disable=SC2016 # a literal ${templateOption:
if grep -rnIF '${templateOption:' "$WS"; then
    echo "Unsubstituted template option (above)" >&2
    exit 1
fi

mkdir "$WS/test-smoke"
cp -R "$TEST_DIR/." "$REPO_ROOT/test/test-utils/test-utils.sh" "$WS/test-smoke/"
cp -R "$REPO_ROOT/test/fixtures" "$WS/test-smoke/fixtures"

if [ -n "${SMOKE_NUGET_SOURCE:-}" ]; then
    protocol=3
    case $SMOKE_NUGET_SOURCE in */api/v2 | */api/v2/) protocol=2 ;; esac
    cat >"$WS/NuGet.Config" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="smoke" value="$SMOKE_NUGET_SOURCE" protocolVersion="$protocol" />
  </packageSources>
</configuration>
EOF
fi

REMOTE_ENV=""
if [ "$TEMPLATE_ID" = python ] && [ -n "${SMOKE_PIP_MIRROR:-}" ]; then
    base=$(sed -n 's/^FROM //p' "$WS/.devcontainer/Dockerfile")
    docker run --rm --label "azsqldc.smoke=$PROJECT" -e PIP_INDEX_URL="$SMOKE_PIP_MIRROR" \
        -v "$WS/test-smoke:/smoke" "$base" \
        bash -c 'pip download -q --only-binary=:all: -d /smoke/wheels -r /smoke/requirements.txt && python /smoke/verify_wheels.py /smoke/wheels'
    REMOTE_ENV="--remote-env PIP_NO_INDEX=1 --remote-env PIP_FIND_LINKS=/workspace/test-smoke/wheels"
fi

if [ "$MODE" = nodb ]; then
    # No SQL Server on this host (arm64 CI has no amd64 emulation): the db service becomes an idle
    # native container, and postCreateCommand (which publishes to SQL Server) is skipped.
    cat >"$WS/.devcontainer/nodb.yml" <<EOF
services:
  db:
    image: $(sed -n 's/^FROM //p' "$WS/.devcontainer/Dockerfile")
    platform: $PLATFORM
    command: sleep infinity
    healthcheck:
      test: ["CMD", "true"]
      interval: 2s
EOF
    perl -0pi -e '$n += s/"dockerComposeFile": "docker-compose.yml"/"dockerComposeFile": ["docker-compose.yml", "nodb.yml"]/; $n += s/"postCreateCommand": "[^"]*"/"postCreateCommand": "true"/; END { exit($n == 2 ? 0 : 1) }' "$WS/.devcontainer/devcontainer.json"
fi

# S5 precondition: the dacpac can only come from this up.
if [ -n "$(find "$WS" \( -name bin -o -name obj -o -name '*.dacpac' \) -print)" ]; then
    echo "Build outputs present before up" >&2
    exit 1
fi
touch "$WS/test-smoke/.before-up"

# shellcheck disable=SC2086 # DEVCONTAINER and REMOTE_ENV are word lists
$DEVCONTAINER up --workspace-folder "$WS" $REMOTE_ENV

if [ -z "$(docker ps -q --filter "label=com.docker.compose.project=$PROJECT" --filter label=com.docker.compose.service=app)" ]; then
    echo "No running app container in compose project $PROJECT; teardown would miss this stack" >&2
    exit 1
fi
