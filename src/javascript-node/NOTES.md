
This template sets up a Node.js development environment with a local SQL Server 2025 container and a sample database. The database schema lives in a SQL Database project that targets Azure SQL Database.

Use it in VS Code with the Dev Containers extension, in GitHub Codespaces, or with the Dev Container CLI.

## What the template creates

Docker Compose runs two containers:

- `app` is the container you work in. It uses `mcr.microsoft.com/devcontainers/javascript-node` on Debian 13 (trixie).
- `db` runs SQL Server 2025 from `mcr.microsoft.com/mssql/server:2025-latest`, Developer edition (`MSSQL_PID=EnterpriseDeveloper`).

The `app` container shares the network of the `db` container. From inside `app`, SQL Server is at `localhost,1433`.

When the container is created, `postCreateCommand` builds the SQL Database project in `database/Library`. Then it publishes the result to SQL Server with SqlPackage. You start with a `Library` database that already has data in it.

### How Azure SQL Database compatibility works

The local engine is SQL Server 2025, not Azure SQL Database. The SQL Database project sets its target platform to Azure SQL Database (`SqlAzureV12DatabaseSchemaProvider`). If the schema uses anything Azure SQL Database doesn't support, the project build fails. That build is the compatibility check. The local engine is not.

The build checks the schema only. Test your app against Azure SQL Database before you ship it. To learn more, see [Target platform](https://learn.microsoft.com/sql/tools/sql-database-projects/concepts/target-platform?view=sql-server-ver17).

## Create the dev container

### VS Code

1. Install Docker and the Dev Containers extension. See [Developing inside a container](https://code.visualstudio.com/docs/devcontainers/containers).
1. Open your project folder in VS Code.
1. Press <kbd>F1</kbd> and run **Dev Containers: Add Dev Container Configuration Files...**.
1. Select **Show All Definitions...**, type **Azure SQL**, and select the `javascript-node` template.
1. Pick the options, then run **Dev Containers: Reopen in Container**.

The first build pulls both images and takes a few minutes.

### GitHub Codespaces

1. Open a codespace on your repository.
1. Press <kbd>F1</kbd> and run **Codespaces: Add Dev Container Configuration Files...**.
1. Select **Show All Definitions...**, type **Azure SQL**, and select the `javascript-node` template.
1. Run **Codespaces: Rebuild Container**.

### Dev Container CLI

```bash
devcontainer templates apply -t ghcr.io/microsoft/azuresql-devcontainers/javascript-node
devcontainer up --workspace-folder .
```

To pick an image variant, pass it as a template argument:

```bash
devcontainer templates apply -t ghcr.io/microsoft/azuresql-devcontainers/javascript-node \
  -a '{"imageVariant":"22-trixie"}'
```

## Image variants

| `imageVariant` | What you get |
|---|---|
| `24-trixie` (default) | Node.js 24 on Debian 13. |
| `22-trixie` | Node.js 22 on Debian 13. |

## Apple Silicon and other Arm64 hosts

The `app` container runs natively on arm64. SQL Server 2025 has no arm64 image, so the `db` container runs as `linux/amd64` under emulation. Docker Desktop and OrbStack run it with Rosetta.

Microsoft does not test or support SQL Server under emulation. See the [SQL Server 2025 on Linux release notes](https://learn.microsoft.com/sql/linux/sql-server-linux-release-notes-2025?view=sql-server-ver17). On a Mac, the SQL Server container works for local development, but outside Microsoft's support. GitHub Codespaces and other x64 hosts run SQL Server natively.

SQL Server occasionally crashes while it starts, dumping core, and the container build then stops because the `db` service never becomes healthy. We saw it 1 start in 37 under emulation on an Apple Silicon Mac, and once on a native x64 GitHub Actions runner, so it is not specific to emulation. Run **Dev Containers: Rebuild Container** again, or restart the `db` container.

Podman on macOS is known to crash SQL Server 2025. See [microsoft/mssql-docker#943](https://github.com/microsoft/mssql-docker/issues/943).

## Tools in the container

- The .NET 10 SDK, from the dotnet Dev Container Feature. The SQL Database project build and SqlPackage need it.
- SqlPackage, installed as a .NET tool and on `PATH`.
- `sqlcmd` from go-sqlcmd v1.10.0.
- Azure CLI with Bicep.
- Azure Developer CLI (`azd`).
- Docker CLI, which talks to the host's Docker engine through the docker-outside-of-docker Feature.

## VS Code extensions

The template installs `ms-mssql.mssql`. Its extension pack adds the SQL Database Projects extension. The template also installs the JavaScript and Node.js extensions. See `.devcontainer/devcontainer.json` for the full list.

The MSSQL extension has a connection profile named **LocalDev**. It connects to `localhost,1433` as `sa`.

GitHub Copilot is not in the list. Current VS Code ships GitHub Copilot Chat built in, and asking for `github.copilot` or `github.copilot-chat` makes the extension install fail, because a built-in extension cannot be replaced from the Marketplace. On older VS Code, install GitHub Copilot yourself.

## Connect from Node.js

Add the `mssql` package to your project:

```bash
npm install mssql
```

```javascript
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

main();
```

`trustServerCertificate: true` skips TLS certificate validation. Use it only against the local container.

## VS Code tasks

To run a task, press <kbd>F1</kbd>, run **Tasks: Run Task**, and pick the task.

![Run a VS Code task](https://raw.githubusercontent.com/microsoft/azuresql-devcontainers/main/docs/images/vscode-azure-sql-devcontainers-tasks.png)

![VS Code task list](https://raw.githubusercontent.com/microsoft/azuresql-devcontainers/main/docs/images/vscode-azure-sql-devcontainers-task-list.png)

If VS Code asks about scanning the task output, select **Continue without scanning the task output**.

![Continue without scanning the task output](https://raw.githubusercontent.com/microsoft/azuresql-devcontainers/main/docs/images/vscode-azure-sql-devcontainers-task-continue.png)

### 1. Verify database schema and data

Opens `scripts/verifyDatabase.sql`, which queries the sample tables. Run the script in the MSSQL extension and pick the **LocalDev** connection.

![Run the SQL script](https://raw.githubusercontent.com/microsoft/azuresql-devcontainers/main/docs/images/vscode-azure-sql-devcontainers-task-sql-run.png)

![Pick the LocalDev connection](https://raw.githubusercontent.com/microsoft/azuresql-devcontainers/main/docs/images/vscode-azure-sql-devcontainers-task-sql-profile.png)

![Query results](https://raw.githubusercontent.com/microsoft/azuresql-devcontainers/main/docs/images/vscode-azure-sql-devcontainers-task-sql-results.png)

### 2. Build SQL Database project

Runs `dotnet build` in `database/Library`. The output is `database/Library/bin/Debug/Library.dacpac`. If the build fails, check the errors for objects that Azure SQL Database doesn't support.

If this task fails once right after the container is created with `The process cannot access the file '/workspace/database/Library/bin/Debug/Library.dacpac' because it is being used by another process`, the post-create publish was still finishing. Run the task again.

![SQL Database project build output](https://raw.githubusercontent.com/microsoft/azuresql-devcontainers/main/docs/images/vscode-azure-sql-devcontainers-task-project-build.png)

### 3. Publish SQL Database project

Publishes the project to the local SQL Server with SqlPackage, using the `sa` password from `.devcontainer/.env`. Run it after you change the schema. SqlPackage compares the project with the database and applies the changes.

![SQL Database project publish output](https://raw.githubusercontent.com/microsoft/azuresql-devcontainers/main/docs/images/vscode-azure-sql-devcontainers-task-project-publish.png)

## Sample database

The `Library` database has:

- Tables `dbo.authors`, `dbo.books`, and `dbo.books_authors`.
- View `dbo.vw_books_details`.
- Stored procedure `dbo.stp_get_all_cowritten_books_by_author`.
- Seed data with 5 authors and 24 books.

To change the schema, edit the `.sql` files in `database/Library`, then run tasks 2 and 3.

## Change the sa password

`MSSQL_SA_PASSWORD` in `.devcontainer/.env` sets the `sa` password. SQL Server, the post-create script, and task 3 read it. The **LocalDev** connection profile in `.devcontainer/devcontainer.json` picks it up through `${containerEnv:MSSQL_SA_PASSWORD}`, which the dev container tooling resolves from the container's environment when the container is created. (`${env:...}` does not work here: VS Code writes connection settings as they are, so the profile would arrive with an empty password.)

The default is a development-only password, and it's public in this repository. Change it for anything beyond local development: edit `MSSQL_SA_PASSWORD` in `.devcontainer/.env`, then rebuild the container. That is the only place the password lives; the LocalDev profile follows it. SQL Server requires at least eight characters from three of these four sets: uppercase letters, lowercase letters, digits, and symbols. After you change it, rebuild the container.

## Ports

`forwardPorts` in `.devcontainer/devcontainer.json` forwards ports `3000` and `1433`. Add the ports your app uses there. Use `forwardPorts` instead of `ports` in `docker-compose.yml`, because only `forwardPorts` works in Codespaces.

## Add another service

Add the service to `.devcontainer/docker-compose.yml`. To reach it on `localhost` from the `app` container, put it on the `db` container's network:

```yaml
network_mode: service:db
```

## Troubleshooting: restricted networks

Some corporate networks block the public package registries. The symptom is a container that builds and then fails while it is created, in `onCreateCommand` or `postCreateCommand`, with a connection reset from one of these hosts:

| Host | Used by |
|---|---|
| `api.nuget.org` | SqlPackage, the SQL Database project build, the Aspire CLI |
| `files.pythonhosted.org` | `pip install mssql-python` (python template) |
| `registry.npmjs.org` | `npm install` in your own project (javascript-node template) |

Point the tools at the feeds your organization allows before you rebuild:

- NuGet: add a `NuGet.Config` in the workspace root with your feed.
- pip: set `PIP_INDEX_URL` in `remoteEnv` in `.devcontainer/devcontainer.json`, or add a `pip.conf`.
- npm: `npm config set registry <your registry>`.

If a window is closed or a rebuild is interrupted while the container is still being created, VS Code stops the containers, and later commands report `Error: No such container`. Run **Dev Containers: Rebuild Container**; the templates rebuild from scratch and publish the database again.

## Learn more

- [What are SQL database projects?](https://learn.microsoft.com/sql/tools/sql-database-projects/sql-database-projects?view=sql-server-ver17)
- [SqlPackage Publish](https://learn.microsoft.com/sql/tools/sqlpackage/sqlpackage-publish?view=sql-server-ver17)
- [SQL Server Linux containers](https://learn.microsoft.com/sql/linux/install-upgrade/quickstart-install-docker?view=sql-server-ver17)
- [Dev Container templates](https://containers.dev/templates)
- [All Azure SQL Database Dev Container templates](https://github.com/microsoft/azuresql-devcontainers)
