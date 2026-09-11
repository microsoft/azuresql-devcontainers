"""Prints the number of books in the Library sample database. Any error raises, so the exit code is non-zero."""
import os

import mssql_python

conn = mssql_python.connect(
    "Server=localhost,1433;Database=Library;UID=sa;"
    f"PWD={{{os.environ['MSSQL_SA_PASSWORD']}}};"
    "Encrypt=yes;TrustServerCertificate=yes;"
)
cursor = conn.cursor()
cursor.execute("SELECT COUNT(*) FROM dbo.books")
print(cursor.fetchone()[0])
conn.close()
