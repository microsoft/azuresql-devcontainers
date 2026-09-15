#!/usr/bin/env bash
# Manual mutation testing. Each mutant is one plausible bug, applied to a fresh copy of the
# committed tree (never the working tree). The python template is brought up from that copy and
# the smoke test must fail with the check the bug breaks.
#
# A mutant may edit several places in one file: separate the texts and the replacements with ";;".
# Proof that a mutant ran: each replacement must match exactly once; the workspace the stack ran
# from must contain the mutated text; and the log must contain the expected "FAIL: <check>" line,
# which only a smoke-test run prints. A mutant that fails some other way counts as survived.
#
# Usage: test/mutants.sh   (environment: as .github/actions/smoke-test/build.sh; MUTANTS_OUT)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${MUTANTS_OUT:-${TMPDIR:-/tmp}/azsqldc-mutants}
TEMPLATE=python
rm -rf "$OUT"
mkdir -p "$OUT"

# shellcheck disable=SC2016 # literal shell text in the mutants
# id | file | check that must fail | text | replacement (last, so it may contain |)
MUTANTS='seed-row|src/python/database/Library/postDeployment.sql|S5 24 books_authors|IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 5 AND book_id = 1023)|IF 1 = 0
no-publish|src/python/.devcontainer/sql/postCreateCommand.sh|S5 5 authors|sqlpackage /Action:Publish|true /Action:Publish
engine-2022|src/python/.devcontainer/docker-compose.yml|S4 engine major version 17|mssql/server:2025-latest;;MSSQL_PID: EnterpriseDeveloper|mssql/server:2022-latest;;MSSQL_PID: Developer
edition-express|src/python/.devcontainer/docker-compose.yml|S4 edition|MSSQL_PID: EnterpriseDeveloper|MSSQL_PID: Express
target-sql170|src/python/database/Library/Library.sqlproj|S10 Azure target rejects fixture|SqlAzureV12DatabaseSchemaProvider|Sql170DatabaseSchemaProvider
sample-query|test/python/test_sql_connection.py|S7 mssql-python sample prints 24|FROM dbo.books|FROM dbo.authors
unbounded-wait|src/python/.devcontainer/sql/postCreateCommand.sh|S11 wrong password fails loudly|if [ "$attempt" -eq 10 ]; then exit 1; fi|if [ "$attempt" -eq 10 ]; then break; fi
sqlcmd-wrong-arch|src/python/.devcontainer/sql/installSQLtools.sh|S1/S2 native sqlcmd|arch=$(dpkg --print-architecture)|arch=amd64
build-failure-ignored|src/python/.devcontainer/sql/postCreateCommand.sh|S16 a failed build is never published|dotnet build database/Library|dotnet build database/Library || true
outputs-removed-after-up|src/python/.devcontainer/sql/postCreateCommand.sh|S5 dacpac built during this up|/TargetTrustServerCertificate:True|/TargetTrustServerCertificate:True && rm -rf database/Library/bin database/Library/obj
task2-wrong-cwd|src/python/.vscode/tasks.json|S17 task 2 builds the project|"cwd": "${workspaceFolder}/database/Library"|"cwd": "${workspaceFolder}"
profile-placeholder|src/python/.devcontainer/devcontainer.json|S18 the LocalDev profile authenticates|"password": "${containerEnv:MSSQL_SA_PASSWORD}"|"password": "${env:MSSQL_SA_PASSWORD}"'

total=0 killed=0
while IFS='|' read -r id file check from to <&3; do
    total=$((total + 1))
    dir="$OUT/$id"
    mkdir -p "$dir/tree"
    git -C "$ROOT" archive HEAD | tar -x -C "$dir/tree"
    FROM=$from TO=$to perl -0pi -e '
        @f = split /;;/, $ENV{FROM}; @t = split /;;/, $ENV{TO};
        for $i (0 .. $#f) { $n = s/\Q$f[$i]\E/$t[$i]/g; $bad = 1 if $n != 1 }
        END { exit($bad || @f != @t ? 1 : 0) }' "$dir/tree/$file" ||
        { echo "mutant $id: each of '$from' must occur exactly once in $file" >&2; exit 2; }

    rc=0
    (
        export RUN_TAG="m$total" WORK_ROOT="$dir/ws"
        smoke="$dir/tree/.github/actions/smoke-test"
        "$smoke/build.sh" "$TEMPLATE" && "$smoke/test.sh" "$TEMPLATE"
    ) </dev/null >"$dir/log" 2>&1 || rc=$? # stdin closed: the Dev Container CLI would eat the mutant list

    case $file in
        src/$TEMPLATE/*) ran=${file#src/"$TEMPLATE"/} ;;
        test/*) ran=test-smoke/$(basename "$file") ;;
    esac
    ws=$(cat "$dir"/ws/*.workspace)
    nl=$'\n'
    while IFS= read -r edit; do
        if ! grep -qF -- "$edit" "$ws/$ran"; then
            echo "mutant $id: the workspace $ws does not contain '$edit'; nothing was proven" >&2
            exit 2
        fi
    done <<<"${to//;;/$nl}"
    if [ "$rc" -ne 0 ] && grep -q "^FAIL: $check" "$dir/log"; then
        killed=$((killed + 1))
        echo "KILLED   $id: '$check' failed (exit $rc; ran from $ws)"
    else
        echo "SURVIVED $id: exit $rc, no 'FAIL: $check' (log: $dir/log)"
    fi
done 3<<<"$MUTANTS"

listed=$(grep -c . <<<"$MUTANTS")
echo "mutation: $killed/$total killed ($listed listed)"
[ "$total" -eq "$listed" ] || { echo "the runner ran $total of $listed mutants" >&2; exit 2; }
[ "$killed" -eq "$total" ]
