#!/usr/bin/env python3
import pyodbc

# python3 -m venv venv
# source venv/bin/activate
# pip install -r requirements.txt

server = 'localhost'  # Replace with your server name or IP address
database = 'library'  # Replace with your database name
username = 'sa'  # Replace with your username
password = 'P@ssw0rd!'  # Replace with your password
driver = '{ODBC Driver 17 for SQL Server}'

try:
    connection_string = f'DRIVER={driver};SERVER={server};PORT=1433;DATABASE={database};UID={username};PWD={password}'
    conn = pyodbc.connect(connection_string)
    cursor = conn.cursor()
    cursor.execute('SELECT @@VERSION')
    row = cursor.fetchone()
    print('Connected to SQL Server')
    print('SQL Server Version:', row[0])
except Exception as e:
    print('Error:', e)
finally:
    if conn:
        conn.close()