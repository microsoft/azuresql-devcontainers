// Prints the number of books in the Library sample database. Any error ends the process with a non-zero exit code.
using Microsoft.Data.SqlClient;

var builder = new SqlConnectionStringBuilder
{
    DataSource = "localhost,1433",
    InitialCatalog = "Library",
    UserID = "sa",
    Password = Environment.GetEnvironmentVariable("MSSQL_SA_PASSWORD"),
    TrustServerCertificate = true,
};

using var connection = new SqlConnection(builder.ConnectionString);
connection.Open();
using var command = new SqlCommand("SELECT COUNT(*) FROM dbo.books", connection);
Console.WriteLine(command.ExecuteScalar());
