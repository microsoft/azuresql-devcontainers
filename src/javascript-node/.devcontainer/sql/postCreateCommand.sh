#!/usr/bin/env bash
# Builds the SQL Database project, provisions Library, and publishes to Azure SQL Database.
# Runs when the container is created, and from the "3. Publish SQL Database project" task.
set -euo pipefail

step="start"
onExit() {
    local rc=$?
    if [ "$rc" -ne 0 ]; then echo "postCreateCommand.sh failed during: $step (exit $rc)" >&2; fi
}
trap onExit EXIT
cd "$(dirname "$0")/../.."
: "${MSSQL_SA_PASSWORD:?is not set; it comes from .devcontainer/.env}"
export SQLCMDPASSWORD=$MSSQL_SA_PASSWORD

waitForDatabase() {
    local database=$1 attempt
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        if sqlcmd -S localhost -d "$database" -U sa -C -l 5 -b -Q "SELECT 1" >/dev/null; then return; fi
        if [ "$attempt" -eq 10 ]; then return 1; fi
        sleep 3
    done
}

step="wait for Azure SQL Database at localhost,1433"
echo "==> $step"
waitForDatabase master

step="build database/Library"
echo "==> $step"
dotnet build database/Library -nodeReuse:false

step="provision Library through master"
echo "==> $step"
sqlcmd -S localhost -d master -U sa -C -b -Q "IF DB_ID('Library') IS NULL CREATE DATABASE [Library];"

step="wait for Library"
echo "==> $step"
waitForDatabase Library

step="publish database/Library/bin/Debug/Library.dacpac to the Library database"
echo "==> $step"
sqlpackage /Action:Publish \
    /SourceFile:database/Library/bin/Debug/Library.dacpac \
    /TargetServerName:localhost /TargetDatabaseName:Library \
    /TargetUser:sa /TargetPassword:"$MSSQL_SA_PASSWORD" /TargetTrustServerCertificate:True
