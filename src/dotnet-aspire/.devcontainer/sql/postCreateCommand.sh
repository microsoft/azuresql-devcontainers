#!/bin/bash

# Setting variables
dacpac="false"
# sqlfiles="false"

# Load SA_PASSWORD from .env file
export $(grep -v '^#' .devcontainer/.env | xargs)
SApassword=$SA_PASSWORD

# Parameters
dacpath=$1
# sqlpath=$2

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

# for f in $sqlpath/*
# do
#     if [ $f == $sqlpath/*".sql" ]
#     then
#         sqlfiles="true"
#         echo "Found SQL file $f"
#     fi
# done

# if [ $sqlfiles == "true" ]
# then
#     for f in $sqlpath/*
#     do
#         if [ $f == $sqlpath/*".sql" ]
#         then
#             echo "Executing $f"
#             sqlcmd -S localhost -U sa -P $SApassword -d master -i $f
#         fi
#     done
# fi

if [ $dacpac == "true" ] 
then
    for f in $dacpath/*
    do
        if [ $f == $dacpath/*".dacpac" ]
        then
            dbname=$(basename $f ".dacpac")
            echo "Deploying dacpac $f"
            /opt/sqlpackage/sqlpackage /Action:Publish /SourceFile:$f /TargetServerName:localhost /TargetDatabaseName:$dbname /TargetUser:sa /TargetPassword:$SApassword /TargetTrustServerCertificate:True
        fi
    done
fi

# if [ $SApassword == "P@ssw0rd!" ]
# then
#     echo "$(tput setaf 1)WARNING$(tput sgr0): you are using the default sample password. If you want to change it, execute the following command"
#     echo "sqlcmd -S localhost -U sa -P $SApassword -d master -Q \"ALTER LOGIN sa WITH PASSWORD = '<enterStrongPasswordHere>' \""
# fi