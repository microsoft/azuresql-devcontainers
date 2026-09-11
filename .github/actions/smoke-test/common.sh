#!/usr/bin/env bash
# Sourced by build.sh and test.sh: where a template is tested, and how its stack is torn down.
# Runs on Linux (CI) and macOS (bash 3.2), so no bash 4 features.
#
# Optional environment:
#   IMAGE_VARIANT  imageVariant to test (default: the template's default)
#   PLATFORM       linux/amd64 or linux/arm64 for the app container (default: the Docker engine's)
#   MODE           full (default) or nodb: app container only, for hosts that can't run SQL Server
#   RUN_TAG        part of the workspace and compose project name, so parallel CI jobs and local
#                  runs never share a stack (default: local)
#   WORK_ROOT      parent directory of the test workspace (default: $RUNNER_TEMP or /tmp)
#   DEVCONTAINER   Dev Container CLI command (default: npx -y @devcontainers/cli@0.89.0)
# shellcheck disable=SC2034 # the variables are used by the scripts that source this file
set -euo pipefail

TEMPLATE_ID=${1:?usage: $0 <template-id>}
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
SRC_DIR=$REPO_ROOT/src/$TEMPLATE_ID
if [ ! -f "$SRC_DIR/devcontainer-template.json" ]; then
    echo "Unknown template: $TEMPLATE_ID" >&2
    exit 2
fi

IMAGE_VARIANT=${IMAGE_VARIANT:-$(jq -er .options.imageVariant.default "$SRC_DIR/devcontainer-template.json")}
PLATFORM=${PLATFORM:-linux/$(docker version --format '{{.Server.Arch}}')}
MODE=${MODE:-full}
ARCH=${PLATFORM#linux/}
case $ARCH in
    amd64) EXPECTED_ARCH=x86_64 ;;
    arm64) EXPECTED_ARCH=aarch64 ;;
    *) echo "Unsupported platform: $PLATFORM" >&2; exit 2 ;;
esac
case $TEMPLATE_ID in
    dotnet | dotnet-aspire) EXPECTED_DOTNET_MAJOR=${IMAGE_VARIANT%%.*} ;;
    *) EXPECTED_DOTNET_MAJOR=10 ;; # the dotnet Feature, pinned to 10.0
esac
case $TEMPLATE_ID in
    dotnet-aspire) TEST_DIR=$REPO_ROOT/test/dotnet ;; # same checks and sample; test.sh adds the Aspire ones
    *) TEST_DIR=$REPO_ROOT/test/$TEMPLATE_ID ;;
esac

# One workspace per build, never reused: a path deleted and recreated at once can hit a stale file
# sharing cache on macOS Docker engines. build.sh records it in $POINTER; test.sh reads it.
BASE=${WORK_ROOT:-${RUNNER_TEMP:-/tmp}}/azsqldc-${RUN_TAG:-local}-$TEMPLATE_ID-$IMAGE_VARIANT-$ARCH-$MODE
POINTER=$BASE.workspace
useWorkspace() {
    WS=$1
    # The Dev Container CLI names the compose project after the workspace folder; build.sh asserts it.
    PROJECT=$(basename "$WS" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')_devcontainer
}
WS="" PROJECT=""
if [ -f "$POINTER" ]; then useWorkspace "$(cat "$POINTER")"; fi
DEVCONTAINER=${DEVCONTAINER:-npx -y @devcontainers/cli@0.89.0}
# Applies to the app image build; the db service pins its own platform.
export DOCKER_DEFAULT_PLATFORM=$PLATFORM

# Removes this workspace's containers, volumes, network, and the app images built for it.
# Touches nothing outside compose project $PROJECT; the shared SQL Server image stays.
teardown() {
    local id images="" image
    [ -n "$PROJECT" ] || return 0
    for id in $(docker ps -aq --filter "label=com.docker.compose.project=$PROJECT"); do
        images="$images $(docker inspect --format '{{.Image}}' "$id")"
    done
    docker compose -p "$PROJECT" down -v --remove-orphans
    images="$images $(docker images -q --no-trunc --filter "reference=vsc-$(basename "$WS" | tr '[:upper:]' '[:lower:]')-*") $(docker images -q --no-trunc --filter "reference=$PROJECT*")"
    # shellcheck disable=SC2086 # images is a word list
    for image in $(printf '%s\n' $images | sort -u); do
        if docker image inspect --format '{{join .RepoTags " "}}' "$image" | grep -q 'mcr.microsoft.com/'; then continue; fi
        docker image rm -f "$image" >/dev/null
    done
}
