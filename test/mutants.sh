#!/usr/bin/env bash
# Manual mutation testing. Each mutant is one plausible bug, applied to a fresh copy of the
# committed tree (never the working tree). The python template is brought up from that copy and
# the smoke test must fail with the check the bug breaks.
#
# Proof that a mutant ran: the replacement must match exactly once; the workspace the stack ran
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
# id | file | text | replacement | check that must fail
MUTANTS='seed-row|src/python/database/Library/postDeployment.sql|IF NOT EXISTS (SELECT 1 FROM dbo.books_authors WHERE author_id = 5 AND book_id = 1023)|IF 1 = 0|S5 24 books_authors
no-publish|src/python/.devcontainer/sql/postCreateCommand.sh|sqlpackage /Action:Publish|true /Action:Publish|S5 5 authors
engine-2022|src/python/.devcontainer/docker-compose.yml|mssql/server:2025-latest|mssql/server:2022-latest|S4 engine major version 17
edition-express|src/python/.devcontainer/docker-compose.yml|MSSQL_PID: EnterpriseDeveloper|MSSQL_PID: Express|S4 edition
target-sql170|src/python/database/Library/Library.sqlproj|SqlAzureV12DatabaseSchemaProvider|Sql170DatabaseSchemaProvider|S10 Azure target rejects fixture
sample-query|test/python/test_sql_connection.py|FROM dbo.books|FROM dbo.authors|S7 mssql-python sample prints 24
unbounded-wait|src/python/.devcontainer/sql/postCreateCommand.sh|if [ "$attempt" -eq 10 ]; then exit 1; fi|if [ "$attempt" -eq 10 ]; then break; fi|S11 wrong password fails loudly'

total=0 killed=0
while IFS='|' read -r id file from to check <&3; do
    total=$((total + 1))
    dir="$OUT/$id"
    mkdir -p "$dir/tree"
    git -C "$ROOT" archive HEAD | tar -x -C "$dir/tree"
    FROM=$from TO=$to perl -0pi -e '$n = s/\Q$ENV{FROM}\E/$ENV{TO}/g; END { exit($n == 1 ? 0 : 1) }' "$dir/tree/$file" ||
        { echo "mutant $id: '$from' does not occur exactly once in $file" >&2; exit 2; }

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
    if ! grep -qF -- "$to" "$ws/$ran"; then
        echo "mutant $id: the workspace $ws does not contain the mutation; nothing was proven" >&2
        exit 2
    fi
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
