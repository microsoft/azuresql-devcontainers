#!/bin/bash

echo "Installing Go-SQLCmd ..."
curl https://packages.microsoft.com/keys/microsoft.asc | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc
sudo add-apt-repository "$(wget -qO- https://packages.microsoft.com/config/ubuntu/20.04/prod.list)"
sudo apt-get update
sudo apt-get install -y sqlcmd
echo "Go-SQLCmd installed."

echo "Installing Sqlpackage ..."
curl -sSL -o sqlpackage.zip "https://aka.ms/sqlpackage-linux"
mkdir -p /opt/sqlpackage
unzip sqlpackage.zip -d /opt/sqlpackage && rm sqlpackage.zip
chmod a+x /opt/sqlpackage/sqlpackage
echo "Sqlpackage installed."

echo "Installing dependencies for SQL Server driver for Python..."
sudo apt-get install -y unixodbc-dev
echo "Dependencies installed."

echo "Installing ODBC driver for SQL Server..."
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
sudo curl https://packages.microsoft.com/config/ubuntu/20.04/prod.list -o /etc/apt/sources.list.d/mssql-release.list
sudo apt-get update
sudo ACCEPT_EULA=Y apt-get install -y msodbcsql17
echo "ODBC driver for SQL Server installed."

echo "Installing Python and pip..."
sudo apt-get install -y python3 python3-pip
echo "Python and pip installed."

echo "Installing SQL Server driver for Python..."
sudo pip3 install pyodbc
echo "SQL Server driver for Python installed."