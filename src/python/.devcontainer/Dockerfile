# [Choice] Python version: 3.12-bookworm, 3.11-bookworm, 3.10-bookworm and 3.12-bullseye, 3.11-bullseye, 3.10-bullseye
FROM mcr.microsoft.com/devcontainers/python:1-${templateOption:imageVariant}

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