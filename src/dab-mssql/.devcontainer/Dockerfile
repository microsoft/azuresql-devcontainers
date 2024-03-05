# [Choice] .NET version: 6.0-focal, 7.0-bullseye
ARG VARIANT="6.0-focal"
FROM mcr.microsoft.com/devcontainers/dotnet:0-${VARIANT}

# Add .NET global tools path
ENV PATH $PATH:/home/vscode/.dotnet:/home/vscode/.dotnet/tools

# [Choice] Node.js version: none, lts/*, 18, 16, 14
ARG NODE_VERSION="none"
RUN if [ "${NODE_VERSION}" != "none" ]; then su vscode -c "umask 0002 && . /usr/local/share/nvm/nvm.sh && nvm install ${NODE_VERSION} 2>&1"; fi

# [Optional] Uncomment this section to install additional OS packages.
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends software-properties-common

# Install SQL Tools: SQLPackage and sqlcmd
COPY sql/installSQLtools.sh installSQLtools.sh
RUN bash ./installSQLtools.sh \
     && apt-get clean -y && rm -rf /var/lib/apt/lists/* /tmp/library-scripts

# Install Data API Builder for vscode user
RUN su vscode -c "dotnet tool install --global Microsoft.DataApiBuilder" 2>&1