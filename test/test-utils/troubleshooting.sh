# Create SQL Library container (manually)
docker run -e 'ACCEPT_EULA=Y' -e 'SA_PASSWORD=P@ssw0rd!' \
    --memory=2048m --cpus=1 --hostname SQL-Library --name SQL-Library \
    --restart unless-stopped -p 1433:1433 -d mcr.microsoft.com/mssql/server:2022-latest

# Deploy Library database (manually)
sqlcmd -S localhost -U sa -P P@ssw0rd! \
    -d master -i test/test-utils/Library.sql \
    -v DatabaseName="Library" DefaultFilePrefix="Library" \
    DefaultDataPath="/var/opt/mssql/data/" DefaultLogPath="/var/opt/mssql/data/" __IsSqlCmdEnabled="True"