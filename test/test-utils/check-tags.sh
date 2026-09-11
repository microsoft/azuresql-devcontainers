#!/usr/bin/env bash
# S13: every imageVariant proposal is a real MCR tag with linux/amd64 and linux/arm64 images.
# The image and tag prefix come from each template's Dockerfile FROM line, so the check follows
# the Dockerfile. Anonymous registry API; needs network. Usage: check-tags.sh [src-dir]
set -euo pipefail

SRC=${1:-$(cd "$(dirname "$0")/../../src" && pwd)}
ACCEPT='application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'
failures=0 checked=0

for template in "$SRC"/*/devcontainer-template.json; do
    dir=$(dirname "$template")
    # shellcheck disable=SC2016 # a literal ${templateOption:imageVariant}
    from=$(sed -n 's#^FROM mcr\.microsoft\.com/\(.*\)\${templateOption:imageVariant}$#\1#p' "$dir/.devcontainer/Dockerfile")
    if [ -z "$from" ]; then
        echo "BROKEN: $dir/.devcontainer/Dockerfile has no 'FROM mcr.microsoft.com/<repo>:<prefix>\${templateOption:imageVariant}' line" >&2
        failures=$((failures + 1))
        continue
    fi
    repo=${from%%:*} prefix=${from#*:}
    if ! jq -e '.options.imageVariant as $o | $o.proposals | index($o.default)' "$template" >/dev/null; then
        echo "MISSING: $(basename "$dir") default imageVariant is not among its proposals" >&2
        failures=$((failures + 1))
    fi
    for variant in $(jq -r '.options.imageVariant.proposals[]' "$template"); do
        checked=$((checked + 1))
        platforms=$(curl -fsS -m 30 -H "Accept: $ACCEPT" "https://mcr.microsoft.com/v2/$repo/manifests/$prefix$variant" |
            jq -r '[.manifests[].platform | select(.os == "linux") | .architecture] | sort | join(",")') || platforms="(request failed)"
        case ",$platforms," in
            *,amd64,*arm64,*) echo "ok: $repo:$prefix$variant [$platforms]" ;;
            *) echo "MISSING: $repo:$prefix$variant [$platforms]" >&2; failures=$((failures + 1)) ;;
        esac
    done
done

echo "check-tags: $checked proposal(s), $failures problem(s)"
[ "$checked" -gt 0 ] && [ "$failures" -eq 0 ]
