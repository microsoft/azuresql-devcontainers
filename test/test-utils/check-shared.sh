#!/usr/bin/env bash
# Shared files: files the four templates share must stay byte-identical, so the copies can't drift.
# Closed world: every file in any template is either listed below as per-template, or must exist
# and be identical in all four. Usage: check-shared.sh [src-dir]
set -euo pipefail

SRC=${1:-$(cd "$(dirname "$0")/../../src" && pwd)}
TEMPLATES="dotnet dotnet-aspire javascript-node python"
PER_TEMPLATE="devcontainer-template.json README.md NOTES.md .devcontainer/devcontainer.json .devcontainer/Dockerfile .vscode/tasks.json"
# Per-template files that must still match within a group of templates.
PAIRS="dotnet:dotnet-aspire:.devcontainer/Dockerfile dotnet:dotnet-aspire:.vscode/tasks.json javascript-node:python:.vscode/tasks.json"

failures=0
paths=$(for t in $TEMPLATES; do (cd "$SRC/$t" && find . -type f | sed 's#^\./##'); done | sort -u)
[ -n "$paths" ] || { echo "No files found under $SRC" >&2; exit 2; }

for path in $paths; do
    case " $PER_TEMPLATE " in *" $path "*) continue ;; esac
    for t in $TEMPLATES; do
        if ! cmp -s "$SRC/dotnet/$path" "$SRC/$t/$path"; then
            echo "DIFFERS: $t/$path vs dotnet/$path" >&2
            failures=$((failures + 1))
        fi
    done
done
for pair in $PAIRS; do
    a=${pair%%:*} rest=${pair#*:}
    b=${rest%%:*} path=${rest#*:}
    if ! cmp -s "$SRC/$a/$path" "$SRC/$b/$path"; then
        echo "DIFFERS: $b/$path vs $a/$path" >&2
        failures=$((failures + 1))
    fi
done

echo "check-shared: $(echo "$paths" | wc -l | tr -d ' ') paths across 4 templates, $failures difference(s)"
[ "$failures" -eq 0 ]
