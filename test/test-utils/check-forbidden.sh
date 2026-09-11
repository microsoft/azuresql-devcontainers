#!/usr/bin/env bash
# Must-find-nothing gates over the tracked files of a git checkout (S14, M4, M5, M6, M8, S12, S15).
# grep exit 1 (nothing found) is the only pass; 0 means a violation, 2+ means the check broke.
# A gate guards spellings, not behavior: each rule lists the spellings it catches, and anything else passes.
# Usage: check-forbidden.sh [repo-dir]
set -euo pipefail

cd "${1:-$(dirname "$0")/../..}"
SELF=test/test-utils/check-forbidden.sh
failures=0

# nothing LABEL CMD...: CMD is a grep-like command; its matches are violations.
nothing() {
    local label=$1 out rc=0
    shift
    out=$("$@") || rc=$?
    case $rc in
        1) echo "ok: $label" ;;
        0) printf 'FORBIDDEN: %s\n%s\n' "$label" "$out" >&2; failures=$((failures + 1)) ;;
        *) echo "BROKEN: $label (exit $rc)" >&2; failures=$((failures + 1)) ;;
    esac
}

tracked() { git -c core.quotePath=false ls-files -- "$@"; } # names as they are, non-ASCII included
binaries() { # tracked, non-empty files under src/ that git considers binary
    local f
    comm -23 <(tracked src | sort) <(git grep -I -l -e '' -- src | sort) | while IFS= read -r f; do
        if [ -s "$f" ]; then echo "$f"; fi
    done
}
unsafeScripts() { # tracked shell scripts whose first command is not set -euo pipefail
    local f
    tracked '*.sh' | while IFS= read -r f; do
        if [ "$(awk '!/^[[:space:]]*(#|$)/ { print; exit }' "$f")" != "set -euo pipefail" ]; then echo "$f"; fi
    done
}
lsOrNone() { local out; out=$("$@") || return 2; [ -n "$out" ] && echo "$out"; } # rc 1 when empty, like grep

# Case-insensitive, and any run of whitespace between words: hostnames ignore case, shells ignore spacing.
nothing "S14/M4 no gated registry reference" git grep -nIi -e 'azurecr\.io' -- . ":!$SELF"
# Credential names like REGISTRY_PASSWORD, ACR_PWD, REGISTRY_PASS, and any registry login command.
nothing "M4 no registry credentials" git grep -nIiE \
    -e '(^|[^[:alnum:]])(registry|acr)[_-]?[[:alnum:]_]*(user(name)?|pass(word|wd)?|pwd|token|secret)' \
    -e '(docker|podman|nerdctl|buildah|oras|helm)[[:space:]]+(registry[[:space:]]+)?login' -e 'az[[:space:]]+acr[[:space:]]+login' \
    -- . ":!$SELF"
nothing "M5 no build outputs or images under src/" grep -iE '/(bin|obj)/|\.(dacpac|dll|pdb|png|jpe?g|gif|svg|webp|ico)$' <(tracked src)
nothing "M5 no bin/ or obj/ tracked anywhere" grep -E '(^|/)(bin|obj)/' <(tracked)
nothing "M5 no binary files under src/" lsOrNone binaries
# shellcheck disable=SC2016 # literal $( and backticks in the patterns
nothing "M6 no global destructive docker command" git grep -nIiE \
    -e 'docker[[:space:]]+(system|volume|image|container|network|builder|buildx)[[:space:]]+prune' \
    -e 'docker[[:space:]]+((volume|image|container|network)[[:space:]]+)?(rm|rmi)[[:space:]][^#]*\$\([[:space:]]*docker' \
    -e 'xargs([[:space:]]+-[[:alnum:]]+)*[[:space:]]+docker[[:space:]]+((volume|image|container|network)[[:space:]]+)?(rm|rmi)' \
    -e '(\$\(|`)[[:space:]]*docker[[:space:]]+(ps|images|volume[[:space:]]+ls|image[[:space:]]+ls|container[[:space:]]+ls)[[:space:]]+-[[:alpha:]]*q[[:alpha:]]*[[:space:]]*(\)|`)' \
    -e 'docker[[:space:]]+(system|volume|image|container|network|builder|buildx)[[:space:]]*\\$' \
    -- test .github ":!$SELF"
nothing "M8 every script starts with set -euo pipefail" lsOrNone unsafeScripts
nothing "M8 no script turns errexit off" git grep -nE -e '^[[:space:]]*set[[:space:]]+\+[[:alpha:]]*e' -e 'set[[:space:]]+\+o[[:space:]]+(errexit|pipefail)' -- '*.sh'
nothing "S12 no Dockerfile swallows a failed step" git grep -nE -e '\|\|' -e 'set[[:space:]]+\+[[:alpha:]]*e' -e ';[[:space:]]*true' -- ':(glob)src/*/.devcontainer/Dockerfile'
nothing "S15 no continue-on-error in workflows" git grep -nIi -e 'continue-on-error' -- .github

echo "check-forbidden: $failures violation(s)"
[ "$failures" -eq 0 ]
