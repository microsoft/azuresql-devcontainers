# DAB calls to HTTP endpoints

# Checking DAB health
curl -v http://localhost:5000

# Checking DAB API for Books and Authors endpoints
curl -s http://localhost:5000/api/Book | jq
curl -s http://localhost:5000/api/Author | jq

# Checking DAB API with query parameters
curl -s http://localhost:5000/api/Book?$first=2 | jq '.value[] | {id, title}'
curl -s http://localhost:5000/api/Author | jq '.value[1] | {id, first_name, last_name}'

# Checking DAB GraphQL
curl -X POST \
    -H "Content-Type: application/json" \
    -d '{"query": "{ books(first: 2, orderBy: {id: ASC}) { items { id title } } }"}' \
    http://localhost:5000/graphql | jq

# Checking DAB GraphQL with variables
curl -X POST \
    -H "Content-Type: application/json" \
    -d '{"query": "query ($first: Int!) { books(first: $first) { items { id title } } }", "variables": {"first": 2}}' \
    http://localhost:5000/graphql | jq

# Checking DAB GraphQL with variables and operation name
curl -X POST \
    -H "Content-Type: application/json" \
    -d '{"query": "query GetBooks($first: Int!) { books(first: $first) { items { id title } } }", "variables": {"first": 2}}' \
    http://localhost:5000/graphql | jq
