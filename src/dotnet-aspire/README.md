
# .NET with Aspire and Azure SQL (dotnet-aspire)

A development environment for .NET Aspire and Azure SQL, enabling streamlined local development and testing.

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| imageVariant | .NET version: | string | 10.0-noble |


This template sets up a .NET and Aspire development environment with a local SQL Server 2025 container and a sample database. The database schema lives in a SQL Database project that targets Azure SQL Database.

Use it in VS Code with the Dev Containers extension, in GitHub Codespaces, or with the Dev Container CLI.

## What the template creates

Docker Compose runs two containers:

- `app` is the container you work in. It uses `mcr.microsoft.com/devcontainers/dotnet` on Ubuntu 24.04 (noble).
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
1. Select **Show All Definitions...**, type **Azure SQL**, and select the `dotnet-aspire` template.
1. Pick the options, then run **Dev Containers: Reopen in Container**.

The first build pulls both images and takes a few minutes.

### GitHub Codespaces

1. Open a codespace on your repository.
1. Press <kbd>F1</kbd> and run **Codespaces: Add Dev Container Configuration Files...**.
1. Select **Show All Definitions...**, type **Azure SQL**, and select the `dotnet-aspire` template.
1. Run **Codespaces: Rebuild Container**.

### Dev Container CLI

```bash
devcontainer templates apply -t ghcr.io/microsoft/azuresql-devcontainers/dotnet-aspire
devcontainer up --workspace-folder .
```

## Image variants

| `imageVariant` | What you get |
|---|---|
| `10.0-noble` (default) | .NET 10 on Ubuntu 24.04. The Aspire AppHost needs the .NET 10 SDK, so this is the only variant. |

## Apple Silicon and other Arm64 hosts

The `app` container runs natively on arm64. SQL Server 2025 has no arm64 image, so the `db` container runs as `linux/amd64` under emulation. Docker Desktop and OrbStack run it with Rosetta.

Microsoft does not test or support SQL Server under emulation. See the [SQL Server 2025 on Linux release notes](https://learn.microsoft.com/sql/linux/sql-server-linux-release-notes-2025?view=sql-server-ver17). On a Mac, the SQL Server container works for local development, but outside Microsoft's support. GitHub Codespaces and other x64 hosts run SQL Server natively.

SQL Server occasionally crashes while it starts, dumping core, and the container build then stops because the `db` service never becomes healthy. We saw it 1 start in 37 under emulation on an Apple Silicon Mac, and once on a native x64 GitHub Actions runner, so it is not specific to emulation. Run **Dev Containers: Rebuild Container** again, or restart the `db` container.

Podman on macOS is known to crash SQL Server 2025. See [microsoft/mssql-docker#943](https://github.com/microsoft/mssql-docker/issues/943).

## Tools in the container

- The .NET 10 SDK.
- SqlPackage, installed as a .NET tool and on `PATH`.
- `sqlcmd` from go-sqlcmd v1.10.0.
- Azure CLI with Bicep.
- Azure Developer CLI (`azd`).
- Docker CLI, which talks to the host's Docker engine through the docker-outside-of-docker Feature.

## VS Code extensions

The template installs `ms-mssql.mssql`. Its extension pack adds the SQL Database Projects extension. The template also installs the C# and .NET extensions. See `.devcontainer/devcontainer.json` for the full list.

The MSSQL extension has a connection profile named **LocalDev**. It connects to `localhost,1433` as `sa`.

GitHub Copilot is not in the list. Current VS Code ships GitHub Copilot Chat built in, and asking for `github.copilot` or `github.copilot-chat` makes the extension install fail, because a built-in extension cannot be replaced from the Marketplace. On older VS Code, install GitHub Copilot yourself.

## Aspire

The container has the Aspire CLI 13.5.x and the `Aspire.ProjectTemplates` templates. The template does not create an Aspire app for you. Create one with `aspire new`, or with `dotnet new` and one of the Aspire templates.

To use the template's SQL Server from your AppHost, add it as a connection string. Aspire then connects to the existing container instead of starting a new one:

```csharp
var sql = builder.AddConnectionString("sql");

builder.AddProject<Projects.MyApi>("api")
    .WithReference(sql);
```

Aspire reads the value from `ConnectionStrings:sql` in the AppHost configuration. Store it as a user secret so the password stays out of source control. Run this in the AppHost project folder:

```bash
dotnet user-secrets set "ConnectionStrings:sql" "Server=localhost,1433;Database=Library;User Id=sa;Password=<your password>;TrustServerCertificate=True"
```

If you want Aspire to run its own SQL Server with `AddSqlServer`, know that `Aspire.Hosting.SqlServer` defaults to the `2022-latest` image. Add `.WithImageTag("2025-latest")` to use SQL Server 2025, like this template.

## VS Code tasks

To run a task, press <kbd>F1</kbd>, run **Tasks: Run Task**, and pick the task.

![Run a VS Code task](https://raw.githubusercontent.com/microsoft/azuresql-devcontainers/main/docs/images/vscode-azure-sql-devcontainers-tasks.png)

![VS Code task list](https://raw.githubusercontent.com/microsoft/azuresql-devcontainers/main/docs/images/vscode-azure-sql-devcontainers-task-list-dotnet.png)

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

### 4. Trust .NET HTTPS certificate

Runs `dotnet dev-certs https --trust`, so ASP.NET Core apps can serve HTTPS in the container. The template sets `SSL_CERT_DIR` so OpenSSL-based clients in the container trust the certificate too, as the [.NET guidance on trusting the development certificate](https://aka.ms/dev-certs-trust) describes.

![VS Code task: trust the .NET HTTPS certificate](https://raw.githubusercontent.com/microsoft/azuresql-devcontainers/main/docs/images/vscode-azure-sql-devcontainers-task-dotnet-cert.png)

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

`forwardPorts` in `.devcontainer/devcontainer.json` forwards ports `5000`, `5001`, `8000`, and `1433`. Add the ports your app uses there. Use `forwardPorts` instead of `ports` in `docker-compose.yml`, because only `forwardPorts` works in Codespaces.

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


---

_Note: This file was auto-generated from the [devcontainer-template.json](https://github.com/microsoft/azuresql-devcontainers/blob/main/src/dotnet-aspire/devcontainer-template.json).  Add additional notes to a `NOTES.md`._
