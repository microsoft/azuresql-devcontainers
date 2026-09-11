// Prints the number of books in the Library sample database. Any error exits with code 1.
const sql = require('mssql');

async function main() {
  const pool = await sql.connect({
    server: 'localhost',
    port: 1433,
    user: 'sa',
    password: process.env.MSSQL_SA_PASSWORD,
    database: 'Library',
    options: { trustServerCertificate: true },
  });
  const result = await pool.request().query('SELECT COUNT(*) AS books FROM dbo.books');
  console.log(result.recordset[0].books);
  await pool.close();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
