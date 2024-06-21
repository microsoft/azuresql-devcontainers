// This is a simple Express server that queries a SQL Server database and returns the results as JSON.
// curl http://localhost:3000/books
// curl http://localhost:3000/authors

require('dotenv').config();
const sql = require('mssql');
const express = require('express');
const app = express();

const config = {
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    server: process.env.DB_SERVER,
    database: process.env.DB_DATABASE,
    options: {
        encrypt: false, // If you're on Windows Azure, set this to true
        enableArithAbort: true
    }
};

const connectAndQuery = async () => {
    try {
        await sql.connect(config);
        const result = await sql.query`SELECT * FROM dbo.books`;
        console.log(result);
    } catch (err) {
        console.error(err);
    }
};

app.get('/books', async (req, res) => {
    try {
        await sql.connect(config);
        const result = await sql.query`SELECT * FROM dbo.books`;
        res.json(result.recordset);
    } catch (err) {
        console.error(err);
        res.status(500).send('An error occurred');
    }
});

app.get('/authors', async (req, res) => {
    try {
        await sql.connect(config);
        const result = await sql.query`SELECT * FROM dbo.authors`;
        res.json(result.recordset);
    } catch (err) {
        console.error(err);
        res.status(500).send('An error occurred');
    }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`Server is running on port ${PORT}`);
    connectAndQuery();

    // Used for automated testing
	if(process.env.REGRESSION_TESTING === 'true') { process.exit(0); }
});
