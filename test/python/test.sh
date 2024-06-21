#!/bin/bash
cd $(dirname "$0")

source test-utils.sh vscode

# Run common tests
checkCommon

# template specific tests
checkExtension "ms-python.python"
checkExtension "ms-python.vscode-pylance"
check "python" python --version
check "pip install" pip install -r requirements.txt
check "test-project: test_sql_connection.py" python ./test_sql_connection.py

# Report
reportResults