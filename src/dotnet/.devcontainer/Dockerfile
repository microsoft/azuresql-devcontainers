FROM mcr.microsoft.com/devcontainers/dotnet:2-${templateOption:imageVariant}

# sqlcmd (go-sqlcmd). SqlPackage is a .NET tool, installed by onCreateCommand in devcontainer.json.
COPY sql/installSQLtools.sh /tmp/installSQLtools.sh
RUN bash /tmp/installSQLtools.sh && rm /tmp/installSQLtools.sh
