#!/bin/bash

# Setting variables
dacpac="false"

# Load SA_PASSWORD from .env file
export $(grep -v '^#' .devcontainer/.env | xargs)
SApassword=$MSSQL_SA_PASSWORD

# Parameters
dacpath=$1

# Extract the project directory from the dacpath
projectDir=$(echo $dacpath | cut -d'/' -f1-2)

echo "SELECT * FROM SYS.DATABASES" | dd of=testsqlconnection.sql
for i in {1..30};
do
    sqlcmd -S localhost -U sa -P $SApassword -d master -i testsqlconnection.sql > /dev/null
    if [ $? -eq 0 ]
    then
        echo "SQL server ready"
        break
    else
        echo "Not ready yet..."
        sleep 1
    fi
done
rm testsqlconnection.sql

for f in $dacpath/*
do
    if [ $f == $dacpath/*".dacpac" ]
    then
        dacpac="true"
        echo "Found dacpac $f"
    fi
done

if [ $dacpac == "true" ] 
then
    # Build the SQL Database project
    echo "Building SQL Database project at $projectDir..."
    dotnet build $projectDir

    for f in $dacpath/*
    do
        if [ $f == $dacpath/*".dacpac" ]
        then
            dbname=$(basename $f ".dacpac")
            # Deploy the dacpac
            echo "Deploying dacpac $f"
            /opt/sqlpackage/sqlpackage /Action:Publish /SourceFile:$f /TargetServerName:localhost /TargetDatabaseName:$dbname /TargetUser:sa /TargetPassword:$SApassword /TargetTrustServerCertificate:True
        fi
    done
fi