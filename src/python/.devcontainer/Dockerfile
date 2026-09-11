FROM mcr.microsoft.com/devcontainers/python:3-${templateOption:imageVariant}

# Azure CLI: Microsoft's apt repository has no Debian 13 (trixie) suite yet, so the azure-cli Feature would
# fall back to Debian's older package. Microsoft Learn's fix for a Debian release without its own suite is
# the bookworm suite; with it listed here, the Feature installs Microsoft's current package.
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/microsoft-azure-cli.gpg \
    && printf 'Types: deb\nURIs: https://packages.microsoft.com/repos/azure-cli/\nSuites: bookworm\nComponents: main\nArchitectures: %s\nSigned-by: /etc/apt/keyrings/microsoft-azure-cli.gpg\n' \
        "$(dpkg --print-architecture)" >/etc/apt/sources.list.d/microsoft-azure-cli-bookworm.sources

# sqlcmd (go-sqlcmd). .NET comes from the dotnet Feature; SqlPackage is a .NET tool, installed by
# onCreateCommand in devcontainer.json.
COPY sql/installSQLtools.sh /tmp/installSQLtools.sh
RUN bash /tmp/installSQLtools.sh && rm /tmp/installSQLtools.sh
