#!/bin/bash

echo "Installing .NET 8 (SDK) ..."

wget https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh

chmod +x ./dotnet-install.sh

./dotnet-install.sh --channel 8.0 
