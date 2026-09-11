-- Valid T-SQL for SQL Server, but Azure SQL Database has no FILESTREAM.
-- Added to a copy of the Library project, it must fail the SqlAzureV12 build with SQL70015.
CREATE TABLE [dbo].[documents] (
    [id]  UNIQUEIDENTIFIER ROWGUIDCOL NOT NULL UNIQUE,
    [doc] VARBINARY (MAX) FILESTREAM NULL
);
