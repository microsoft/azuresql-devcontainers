#!/usr/bin/env bash
# Installs sqlcmd (go-sqlcmd) from its GitHub release, checked against the release's SHA-256.
# There is no current apt package for Debian 12/13 or Ubuntu 24.04, and the old one is x86-only.
set -euo pipefail

version=v1.10.0
arch=$(dpkg --print-architecture)
case $arch in
    amd64) sha256=92516d98c63d99b0994de5b61350c91f6915f9b76f139a59039fbcb225c2e987 ;;
    arm64) sha256=9faaa981f9c374f319ac796dedb4678499b8596c87d5b6c512e9b0e7a3b74f8e ;;
    *) echo "go-sqlcmd has no Linux build for $arch" >&2; exit 1 ;;
esac

tarball=$(mktemp)
curl -fsSL -o "$tarball" "https://github.com/microsoft/go-sqlcmd/releases/download/$version/sqlcmd-linux-$arch.tar.bz2"
echo "$sha256  $tarball" | sha256sum --check --strict -
tar -xjf "$tarball" -C /usr/local/bin sqlcmd
rm "$tarball"
sqlcmd --version
