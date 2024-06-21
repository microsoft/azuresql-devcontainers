# Smoke tests
# .NET
./.github/actions/smoke-test/build-dotnet.sh dotnet
./.github/actions/smoke-test/test-dotnet.sh dotnet

# .NET Aspire
./.github/actions/smoke-test/build-dotnet-aspire.sh dotnet-aspire
./.github/actions/smoke-test/test-dotnet-aspire.sh dotnet-aspire

# Node.js
./.github/actions/smoke-test/build-javascript-node.sh javascript-node
./.github/actions/smoke-test/test-javascript-node.sh javascript-node

# Python
./.github/actions/smoke-test/build-python.sh python
./.github/actions/smoke-test/test-python.sh python

# Remove all containers
docker rm -f $(docker ps -a -q)

# Remove all unused Docker objects...
docker system prune -a -f