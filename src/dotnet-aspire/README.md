
# .NET with Aspire and Azure SQL (dotnet-aspire)

A development environment for .NET Aspire and Azure SQL, enabling streamlined local development and testing.

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| imageVariant | .NET version: | string | 8.0-bookworm |


This Dev Container template enables you to effortlessly explore **.NET Aspire** and **Azure SQL**. In just a few simple steps, you can dive into the capabilities of these powerful technologies.

A **development container** (Dev Container for short) is a running [Docker](https://www.docker.com) container with a well-defined tool/runtime stack and its prerequisites. You can try out Dev Containers with **[GitHub Codespaces](https://github.com/features/codespaces)** or **[Visual Studio Code Dev Containers](https://aka.ms/vscode-remote/containers)**.

To learn more details about all the Azure SQL Database templates, you can explore the template repository at [aka.ms/azuresql-devcontainers](https://aka.ms/azuresql-devcontainers). This repository includes comprehensive information for each Azure SQL template. To learn more about Dev Containers, visit [containers.dev](https://containers.dev/) website, where you find a diverse range of templates.

> **Note:** If you already have a Codespace or Dev Container, you can jump to the [About this template](#about-this-template) section.

## Setting up the development container

### GitHub Codespaces

Follow these steps to open this sample in a Codespaces:

1. Select the Code drop-down menu and select the **Codespaces** tab.
2. Select on **Create codespaces on main** at the bottom of the pane.

For more info, check out the [GitHub documentation](https://docs.github.com/en/free-pro-team@latest/github/developing-online-with-codespaces/creating-a-codespace#creating-a-codespace).

### Visual Studio Code - Dev Containers

Follow these steps to open this sample in a container using the VS Code Dev Containers extension:

1. If you're using a Dev Container for the first time, ensure your system meets the prerequisites in the [getting started steps](https://aka.ms/vscode-remote/containers/getting-started).
2. To use this repository, you can either open the repository in an isolated Docker volume:
    - Press `F1` or `Ctrl+Shift+P` to open the command palette.
    - Select the **Dev Containers: New Dev Container** command.
    - Select the desired Dev Container template for Azure SQL Database, typing `*Azure SQL*`.
    - Select the **.NET with Aspire and Azure SQL (dotnet-aspire)** template
    - Wait for the container to build.
        - Visual Studio Code builds the container based on the selected configuration.
        - The build process might take a few minutes the first time.
        - Subsequent builds are faster.
    - Once the container is built, the repository opens in the Dev Container.

> **Note:** Under the hood, this will use the **Dev Containers: Clone Repository in Container Volume...** command to clone the source code in a Docker volume instead of the local filesystem. [Volumes](https://docs.docker.com/storage/volumes/) are the preferred mechanism for persisting container data.

### About this template

This Dev Container includes a preconfigured database, tailored for use with the Aspire component. This database serves as a foundation for demonstrating how the Aspire component interacts with Azure SQL.

This template creates two containers, one for the Dev Container that includes .NET and Aspire, and one for Microsoft SQL Server. You're connected to the Ubuntu, and from within that container, the MS SQL container is available on **`localhost`** port 1433. The Dev Container also includes supporting scripts in the `.devcontainer/sql` folder used to configure the `Library` sample database.

The SQL container is deployed from the latest developer edition of Microsoft SQL 2022. The database are made available directly in the Codespace/VS Code through the MSSQL extension with a connection labeled **LocalDev**. The default `sa` user password is set using the .devcontainer/.env file. In `.devcontainer/docker-compose.yml`, port `1433` is mapped as the default SQL Server port.

.NET Aspire is a cutting-edge framework crafted for developing cloud-native applications, with a primary focus on containerized environments. Aspire, built with .NET Core, empowers developers to architect scalable and resilient applications optimized for cloud deployment.

**Note:**
While the SQL Server container employs a standard version of SQL Server, all database development within this Dev Container can be validated for Azure SQL Database using the SQL Database Project. The SQL Database project is preconfigured with the target platform set as Azure SQL Database.

#### Visual Code Tasks

This Dev Container template includes multiple tasks that can help with common actions. You can access these tasks by opening the Command Palette in VS Code. Here's how:

1. To open the Command Palette, press <kbd>F1</kbd> or <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>P</kbd>.
2. Type "Run Task" and select "Tasks: Run Task".
3. Choose the task you want to run from the list.

##### Verify database schema and data

This task opens the `verifyDatabase.sql` file in your workspace and executes the SQL query using the `ms-mssql.mssql` extension. This task is optional however it can help you to become familiar with the sample `Library` database tables and data included in this Dev Container template.

##### Build SQL Database project

This task builds the SQL Database project. It runs the command `dotnet build` in the `database/Library` directory of your workspace.

This task is optional, but it's useful to verify the database schema. You can use this SQL Database project to make changes to the database schema and deploy it to the SQL Server container.

#### Deploy SQL Database Project

This task involves deploying the SQL Database project to your SQL Server container. It executes the `postCreateCommand.sh` script found in the `.devcontainer/sql` directory of your workspace.

The `postCreateCommand.sh` script requires one argument: the path to the directory containing the .dacpac file for the SQL Database project. In this scenario, that directory is `database/Library/bin/Debug`.

It utilizes the sqlpackage command-line utility to update the database schema using the .dacpac file, employing authentication credentials from the `.env` file situated in the `.devcontainer` directory.

##### Trust HTTPS certificate for .NET Aspire

This task trusts the HTTPS certificate for the .NET Aspire project. It runs the command `dotnet dev-certs https --trust`.

##### Update .NET SDK

This task ensures that .NET Aspire uses the latest advancements and enhancements provided by the .NET ecosystem, enabling smoother development experiences and potentially addressing any compatibility issues with newer versions of .NET or its related components.

### Changing the sa password

To adjust the sa password, you need to modify the `.env` file located within the `.devcontainer` directory. This password is crucial for the creation of the SQL Server container and the deployment of the Library database using the `database/Library/bin/Debug/Library.dacpac` file.

The password must comply with the following rules:

- It should have a minimum length of eight characters.
- It should include characters from at least three of the following categories: uppercase letters, lowercase letters, numbers, and nonalphanumeric symbols.

### Database deployment

By default, a demo database titled `Library` is created using a DAC package. The deployment process is automated through the `postCreateCommand.sh` script, which is specified in the devcontainer.json configuration:

```json
"postCreateCommand": "bash .devcontainer/sql/postCreateCommand.sh 'database/Library/bin/Debug'"
```

#### Automated Database Deployment

The `postCreateCommand.sh` script handles the database deployment by performing the following steps:

1. Loads the `SA_PASSWORD` from the `.env` file.
1. Waits for the SQL Server to be ready by attempting to connect multiple times.
1. Checks for .dacpac files in the specified directory (`database/Library/bin/Debug`).
1. Deploys each .dacpac file found to the SQL Server.

#### Using the SQL Database Projects Extension

You can use the SQL Database Projects extension to deploy the database schema. The Library.sqlproj project is located in the database/Library folder and can be built using the Build SQL Database project task. The output .dacpac files should be placed in the ./bin/Debug folder for deployment.

### Adding another service

You can add other services to your `.devcontainer/docker-compose.yml` file [as described in Docker's documentation](https://docs.docker.com/compose/compose-file/#service-configuration-reference). However, if you want anything running in this service to be available in the container on localhost, or want to forward the service locally, be sure to add this line to the service config:

```yaml
# Runs the service on the same network as the database container, allows "forwardPorts" in devcontainer.json function.
network_mode: service:db
```

### Using the forwardPorts property

By default, web frameworks and tools often only listen to localhost inside the container. As a result, we recommend using the `forwardPorts` property to make these ports available locally.

This project uses the `5000` and `5001` ports for DAB, and the port `1433` for SQL Server:

```json
"forwardPorts": [5000, 5001, 8000, 1433]
```
> **Note:** You can add additional ports to this list as needed.

The `ports` property in `docker-compose.yml` [publishes](https://docs.docker.com/config/containers/container-networking/#published-ports) rather than forwards the port. This configuration couldn't work in a cloud environment like Codespaces and applications need to listen to `*` or `0.0.0.0` for the application to be accessible externally. Fortunately the `forwardPorts` property doesn't have this limitation.

---

_Note: This file was auto-generated from the [devcontainer-template.json](https://github.com/microsoft/azuresql-devcontainers/blob/main/src/dotnet-aspire/devcontainer-template.json).  Add additional notes to a `NOTES.md`._
