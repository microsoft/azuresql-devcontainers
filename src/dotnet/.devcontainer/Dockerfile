# [Choice] .NET version: 8.0-bookworm, 8.0-jammy, 8.0-bullseye
FROM mcr.microsoft.com/devcontainers/dotnet:1-${templateOption:imageVariant}

# Add .NET global tools path
ENV PATH $PATH:/home/vscode/.dotnet:/home/vscode/.dotnet/tools

# [Optional] Uncomment this section to install additional OS packages.
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends software-properties-common

# Install SQL Tools: SQLPackage and sqlcmd
COPY sql/installSQLtools.sh installSQLtools.sh
RUN bash ./installSQLtools.sh \
     && apt-get clean -y && rm -rf /var/lib/apt/lists/* /tmp/library-scripts