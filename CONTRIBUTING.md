# Contributing to the Bitiq Ecosystem

Welcome to the Bitiq ecosystem! We appreciate your interest in contributing. This guide applies to all Bitiq subprojects, including `example-backend`, future services, and web interfaces that may emerge over time.

## Table of Contents

- [Contributing to the Bitiq Ecosystem](#contributing-to-the-bitiq-ecosystem)
  - [Table of Contents](#table-of-contents)
  - [Code of Conduct](#code-of-conduct)
  - [Project Structure and Philosophy](#project-structure-and-philosophy)
  - [Getting Started](#getting-started)
  - [Using the Ecosystem Repository](#using-the-ecosystem-repository)
  - [Project Lifecycle](#project-lifecycle)
  - [Documentation Standards](#documentation-standards)
  - [Semantic Versioning & Conventional Commits](#semantic-versioning--conventional-commits)
  - [Development Workflow](#development-workflow)
  - [Testing and Quality Assurance](#testing-and-quality-assurance)
  - [Architecture Decisions](#architecture-decisions)
  - [Submitting Changes](#submitting-changes)
  - [Release Process](#release-process)
  - [Support and Contact](#support-and-contact)

## Code of Conduct

All contributors are expected to uphold a respectful, inclusive environment. For full details, please see our Code of Conduct (planned).

## Project Structure and Philosophy

Bitiq is composed of multiple microservices and frontends, each defined with OpenAPI specs and focused on being cloud-agnostic. Our services run on OpenShift, leveraging GitOps and Pipelines for deployment and ODF for storage.

By having a consistent structure (SPEC.md, README.md, TODO.md, CHANGELOG.md, docs/adr), we help newcomers ramp up quickly and ensure that all parts of the ecosystem feel familiar.

## Getting Started

1. Fork and clone the repository you want to contribute to.
2. Refer to that project’s README for environment prerequisites and local run instructions.

## Using the Ecosystem Repository

The `PaulCapestany/ecosystem` repository serves as the central hub for development standards, templates, and guides. It contains:

1. Guides for development patterns and conventions
2. Project management templates (SPEC.md, TODO.md, ADRs, etc.)

When starting a new project or contributing to an existing one:

- Reference the guides for standards and best practices
- Use the templates for creating new documents
- Follow the project lifecycle as defined in the ecosystem repo

To propose changes to standards or templates, open a pull request against the ecosystem repository with your suggested improvements.

## Project Lifecycle

Bitiq follows a structured project lifecycle documented in the Project Lifecycle Guide. The key phases are:

1. Ideation and Specification — Define what needs to be built (SPEC.md)
2. Planning and Task Creation — Break down work into actionable tasks (TODO.md)
3. Development and Implementation — Build the service
4. Testing and Validation — Ensure quality and correctness
5. Deployment and Release — Make the service available
6. Maintenance and Evolution — Support and improve the service

## Documentation Standards

Every project maintains these key documents:

1. SPEC.md: Defines project requirements and specifications
2. TODO.md: Tracks pending development tasks
3. README.md: Setup and usage information
4. CHANGELOG.md: Records notable changes (generated from commits)
5. ADRs: Significant technical decisions in `docs/adr/`

## Semantic Versioning & Conventional Commits

We follow Semantic Versioning and Conventional Commits to keep releases and history clean.

## Development Workflow

1. Review SPEC.md (or create one using the template)
2. Plan tasks in TODO.md
3. Open a feature branch
4. Commit using Conventional Commits
5. Open a PR with clear scope and description

## Testing and Quality Assurance

Add tests where applicable. Follow repository-specific guidelines and Make targets.

## Architecture Decisions

Document significant choices as ADRs in `docs/adr/`.

## Submitting Changes

1. Ensure `make lint` and `make template` pass (for this repo)
2. Use small, reviewable PRs with a single purpose
3. Fill in the PR template and reference relevant issues

## Release Process

Releases follow SemVer. CHANGELOGs are derived from commit history.

## Support and Contact

Open issues or discussions in the repository. For security matters, refer to SECURITY.md.

