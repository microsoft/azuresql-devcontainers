# Azure SQL Database Dev Container Templates

<table style="width: 100%; border-style: none;"><tr>
<td style="width: 140px; text-align: center;"><a href="https://github.com/devcontainers"><img width="128px" src="https://raw.githubusercontent.com/microsoft/fluentui-system-icons/78c9587b995299d5bfc007a0077773556ecb0994/assets/Cube/SVG/ic_fluent_cube_32_filled.svg" alt="devcontainers organization logo"/></a></td>
<td>
<strong>Azure SQL Database Dev Container Templates</strong><br />
Streamlined development environments for Azure SQL Database using Dev Containers.
</td>
</tr></table>

## Overview

In the quest to enhance local development for Azure SQL Database, this repository provides a comprehensive solution leveraging the power of Dev Containers. These templates offer developers a seamless and efficient development environment, enabling them to build applications for Azure SQL Database with ease and confidence. Dev Containers can be utilized in any development environment, including the cloud, promoting consistency across teams and workflows.

## Problem Statement

Developers face significant challenges in setting up efficient local development environments for Azure SQL Database:

- **Lack of Compatibility**: Discrepancies between local development and production environments.
- **Setup Complexity**: Time-consuming manual installations and configurations.
- **Dependency on Cloud Resources**: Increased cloud costs and reliance on internet connectivity.
- **Limited Integration**: Lack of integration with existing Azure development tools.

## Why Dev Containers, Docker, and VS Code?

Dev Containers, Docker, and VS Code are pivotal tools for modern developers:

- **Docker**: Provides portable and reproducible environments.
- **VS Code**: Popular IDE with robust features and extensibility.
- **Dev Containers**: Offer a seamless transition from local development to Azure environments, reducing setup complexity and promoting efficiency.

## Value Proposition

Adopting Dev Containers for Azure SQL Database development offers several advantages:

- **Efficient Local Development**: Streamlines the setup process, saving time and reducing errors.
- **Cost-Efficiency**: Reduces cloud costs by enabling local development.
- **Faster Time-to-Market**: Accelerates development cycles, leading to quicker application releases.
- **Alignment with Cloud-Native Trends**: Supports modern application architectures and frameworks.

## Available Templates

This repository includes Dev Container templates for the following frameworks:

- .NET Aspire

Each template comes with a pre-configured Azure SQL Database, making it easy to start developing right away.

## How to Use the Templates

### 1. Using Supporting Tools

Tools like [Visual Studio Code](https://code.visualstudio.com/) and [GitHub Codespaces](https://docs.github.com/en/codespaces/overview) support Dev Container templates. These tools provide a user-friendly interface to configure and use the templates.

### 2. Using the Dev Container CLI

The [@devcontainers/cli](https://containers.dev/supporting#devcontainer-cli) allows you to apply templates from the supported OCI registry.

#### Example

```sh
devcontainer templates apply --workspace-folder . \
    --template-id ghcr.io/devcontainers/templates/azure-sql:latest
```

## Contributions

### Creating your own collection of templates

The [Dev Container Template specification](https://containers.dev/implementors/templates-distribution/#distribution) outlines a pattern for community members and organizations to self-author Templates in repositories they control.

### Contributing to this repository

This repository will accept improvement and bug fix contributions related to the
[current set of maintained templates](./src).

## Feedback

Issues related to these templates can be reported in [an issue](https://github.com/microsoft/azuresql-devcontainers/issues) in this repository.

# License
Copyright (c) Microsoft Corporation. All rights reserved. <br />
Licensed under the MIT License. See [LICENSE](LICENSE).