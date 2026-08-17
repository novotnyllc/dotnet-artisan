---
name: dotnet-devops
description: Configures .NET CI/CD pipelines (GitHub Actions with setup-dotnet, NuGet cache, reusable workflows; Azure DevOps with DotNetCoreCLI, templates, multi-stage), containerization (multi-stage Dockerfiles, Compose, rootless), packaging (NuGet authoring, source generators, MSIX signing), release management (NBGV, SemVer, changelogs, GitHub Releases), and observability (OpenTelemetry, health checks, structured logging, PII). Spans 18 topic areas. Do not use for application-layer API or UI implementation patterns.
license: MIT
user-invocable: false
---

# dotnet-devops

## Overview

CI/CD, packaging, release management, and operational tooling for .NET. This consolidated skill spans 18 topic areas. Load the appropriate companion file from `references/` based on the routing table below.

## Routing Table

| Topic | Keywords | Description | Companion File |
|-------|----------|-------------|----------------|
| GHA build/test | setup-dotnet, NuGet cache, reporting | GitHub Actions .NET build/test (setup-dotnet, NuGet cache, reporting) | references/gha-build-test.md |
| GHA deploy | Azure Web Apps, GitHub Pages, containers | GitHub Actions deployment (Azure Web Apps, GitHub Pages, containers) | references/gha-deploy.md |
| GHA publish | NuGet push, container images, signing, SBOM | GitHub Actions publishing (NuGet push, container images, signing, SBOM) | references/gha-publish.md |
| GHA patterns | reusable workflows, composite, matrix, cache | GitHub Actions composition (reusable workflows, composite, matrix, cache) | references/gha-patterns.md |
| ADO build/test | DotNetCoreCLI, Artifacts, test results | Azure DevOps .NET build/test (DotNetCoreCLI, Artifacts, test results) | references/ado-build-test.md |
| ADO publish | NuGet push, containers to ACR | Azure DevOps publishing (NuGet push, containers to ACR) | references/ado-publish.md |
| ADO patterns | templates, variable groups, multi-stage | Azure DevOps composition (templates, variable groups, multi-stage) | references/ado-patterns.md |
| ADO unique | environments, approvals, service connections | Azure DevOps exclusive features (environments, approvals, service connections) | references/ado-unique.md |
| Containers | multi-stage Dockerfiles, SDK publish, rootless | .NET containerization (multi-stage Dockerfiles, SDK publish, rootless) | references/containers.md |
| Container deployment | Compose, health probes, CI/CD pipelines | Container deployment (Compose, health probes, CI/CD pipelines) | references/container-deployment.md |
| NuGet authoring | SDK-style, source generators, multi-TFM | NuGet package authoring (SDK-style, source generators, multi-TFM) | references/nuget-authoring.md |
| MSIX | creation, signing, Store, sideload, auto-update | MSIX packaging (creation, signing, Store, sideload, auto-update) | references/msix.md |
| GitHub Releases | creation, assets, notes, pre-release | GitHub Releases (creation, assets, notes, pre-release) | references/github-releases.md |
| Release management | NBGV, SemVer, changelogs, branching | Release lifecycle (NBGV, SemVer, changelogs, branching) | references/release-management.md |
| Observability | OpenTelemetry, health checks, custom metrics | Observability (OpenTelemetry, health checks, custom metrics) | references/observability.md |
| Structured logging | aggregation, sampling, PII, correlation | Log pipelines (aggregation, sampling, PII, correlation) | references/structured-logging.md |
| Add CI | CI/CD scaffold, GHA vs ADO detection | CI/CD scaffolding (GHA vs ADO detection, workflow templates) | references/add-ci.md |
| GitHub docs | README badges, CONTRIBUTING, templates | GitHub documentation (README badges, CONTRIBUTING, templates) | references/github-docs.md |

## Scope

- GitHub Actions workflows (build, test, deploy, publish)
- Azure DevOps pipelines (build, test, publish, environments)
- Container builds and deployment (Docker, Compose)
- NuGet and MSIX packaging
- Release management (NBGV, SemVer, changelogs)
- Observability and structured logging (OpenTelemetry)
- GitHub repository documentation and CI scaffolding

## Out of scope

- API/backend code patterns -> [skill:dotnet-api]
- Build system authoring -> [skill:dotnet-tooling]
- Test authoring -> [skill:dotnet-testing]
