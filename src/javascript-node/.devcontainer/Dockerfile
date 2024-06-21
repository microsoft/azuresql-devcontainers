# [Choice] Node.js version: 22-bookworm, 22-bullseye, 20-bookworm, 20-bullseye, 18-bookworm, 18-bullseye
FROM mcr.microsoft.com/devcontainers/javascript-node:1-${templateOption:imageVariant}

# [Optional] Uncomment this section to install additional OS packages.
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends software-properties-common

# Install SQL Tools: SQLPackage, sqlcmd and drivers
COPY sql/installSQLtools.sh installSQLtools.sh
RUN bash ./installSQLtools.sh \
     && apt-get clean -y && rm -rf /var/lib/apt/lists/* /tmp/library-scripts

# Install .NET SDK 8 (for SQL Database projects)
COPY dotnet/install-dotnet.sh install-dotnet.sh
RUN bash ./install-dotnet.sh \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/* /tmp/library-scripts