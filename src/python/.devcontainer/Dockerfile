FROM mcr.microsoft.com/devcontainers/python:3-${templateOption:imageVariant}

# sqlcmd (go-sqlcmd). .NET comes from the dotnet Feature; SqlPackage is a .NET tool, installed by
# onCreateCommand in devcontainer.json.
COPY sql/installSQLtools.sh /tmp/installSQLtools.sh
RUN bash /tmp/installSQLtools.sh && rm /tmp/installSQLtools.sh
