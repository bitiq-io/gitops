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
  - [Semantic Versioning \& Conventional Commits](#semantic-versioning--conventional-commits)
  - [Development Workflow](#development-workflow)
  - [Testing and Quality Assurance](#testing-and-quality-assurance)
  - [Architecture Decisions](#architecture-decisions)
  - [Submitting Changes](#submitting-changes)
  - [Release Process](#release-process)
  - [Support and Contact](#support-and-contact)

## Code of Conduct

All contributors are expected to uphold a respectful, inclusive environment. For full details, please see our [Code of Conduct](./CODE_OF_CONDUCT.md) (not yet implemented, but planned).

## Project Structure and Philosophy

Bitiq is composed of multiple microservices and frontends, each defined with OpenAPI specs and focused on being cloud-agnostic. Our services run on OpenShift, leveraging GitOps and Pipelines for deployment and ODF for storage.

By having a consistent structure (SPEC.md, README.md, TODO.md, CHANGELOG.md, docs/adr), we help newcomers ramp up quickly and ensure that all parts of the ecosystem feel familiar.

## Getting Started

1. **Clone the Repository:**  
   Start by forking and cloning the particular subproject (e.g., `example-backend`).

2. **Set Up Your Environment:**  
   Refer to the project's `README.md` for environment prerequisites, dependencies, and local run instructions.

## Using the Ecosystem Repository

The [`paulcapestany/ecosystem`](https://github.com/paulcapestany/ecosystem) repository serves as the central hub for development standards, templates, and guides. It contains:

1. **Guides Directory:** Contains comprehensive guides like the Golang Microservices Development Guide
2. **Project Management Directory:** Contains the Project Lifecycle Guide and standardized templates for SPEC.md, TODO.md, ADRs, and other documents

When starting a new project or contributing to an existing one:

- **Reference the guides** for development standards and best practices
- **Use the templates** for creating new documents
- **Follow the project lifecycle** as defined in the ecosystem repo

To propose changes to standards or templates, open a pull request against the ecosystem repository with your suggested improvements.

## Project Lifecycle

Bitiq follows a structured project lifecycle as documented in the [Project Lifecycle Guide](https://github.com/paulcapestany/ecosystem/project-management/project-lifecycle.md). The key phases are:

1. **Ideation and Specification** - Define what needs to be built (SPEC.md)
2. **Planning and Task Creation** - Break down work into actionable tasks (TODO.md)
3. **Development and Implementation** - Build the service
4. **Testing and Validation** - Ensure quality and correctness
5. **Deployment and Release** - Make the service available
6. **Maintenance and Evolution** - Support and improve the service

Each phase has specific deliverables and processes that should be followed.

## Documentation Standards

Every Bitiq project must maintain these key documents:

1. **SPEC.md**: Defines project requirements and specifications
   - Created during the ideation phase
   - Follows the [SPEC.md template](https://github.com/paulcapestany/ecosystem/project-management/spec-template.md)
   - Documents what the service should do and why

2. **TODO.md**: Tracks pending development tasks
   - Contains only tasks that have not yet been completed
   - Formatted directly in Conventional Commits syntax
   - Each task can be used directly as a commit message
   - References GitHub issue numbers when applicable
   - Example format:
     ```markdown
     feat(api): implement endpoint X (#123)
     ```

3. **README.md**: Provides setup instructions and usage information
   - Focuses on how to use, set up, and contribute to the service
   - Includes API documentation and examples

4. **CHANGELOG.md**: Records all notable changes
   - Automatically generated from commit history
   - Follows Semantic Versioning structure
   - Should not be manually edited (use proper commit messages instead)

5. **Architecture Decision Records (ADRs)**: Documents significant technical decisions
   - Stored in `docs/adr/` directory
   - Follows the [ADR template](https://github.com/paulcapestany/ecosystem/project-management/adr-template.md)
   - Example: `docs/adr/0001-use-couchbase.md`

## Semantic Versioning & Conventional Commits

We strictly follow [Semantic Versioning (SemVer)](https://semver.org/) and [Conventional Commits](https://www.conventionalcommits.org/) to communicate the impact of changes clearly and maintain clean release notes.

- **MAJOR:** Incompatible API changes.
- **MINOR:** Backward-compatible feature additions.
- **PATCH:** Backward-compatible bug fixes or documentation improvements.

Commit types include `feat`, `fix`, `docs`, `chore`, `refactor`, `perf`, `test`. Append `!` for breaking changes, e.g., `feat!: ...`.

## Development Workflow

1. **Understand Requirements:**
   - Review the SPEC.md document to understand what needs to be built
   - If no SPEC.md exists, create one following the template

2. **Plan Implementation:**
   - Identify tasks in TODO.md or add new ones
   - Break down complex requirements into smaller tasks

3. **Create a Branch:**
   - Branch naming follows Conventional Commits: `feat/implement-x`, `fix/resolve-y`

4. **Code & Test:**
   - Implement features or fixes according to SPEC.md
   - Write tests for all functionality
   - Document architectural decisions in ADRs when significant choices are made

5. **Pull Request (PR):**
   - Open a PR for review
   - Reference the related TODO items and issues in the PR description
   - CI will run tests automatically

6. **Feedback & Revisions:**
   - Expect reviews and possibly requested changes
   - Update code based on feedback

7. **Merge & Release:**
   - Once approved, maintainers merge and update `CHANGELOG.md` according to SemVer
   - Update TODO.md to mark completed tasks

## Testing and Quality Assurance

Each subproject includes instructions on running tests (e.g., `make test` or similar). We aim for comprehensive unit testing, integration testing, and OpenAPI conformance tests where applicable.

Follow these testing guidelines:
- Unit tests for all business logic
- Integration tests for component interactions
- E2E tests for critical user flows
- Performance tests for key operations

## Architecture Decisions

When making significant architectural decisions:

1. **Create an ADR** using the template in the ecosystem repository
2. **Review the ADR** with other contributors
3. **Document the outcome** including alternatives considered
4. **Reference ADRs** in code comments and documentation

This ensures that important decisions are well-documented and future contributors understand why things were built a certain way.

## Submitting Changes

- Open a PR against `main`
- Follow Conventional Commits for your commit messages
- Update both SPEC.md (if requirements changed) and TODO.md (to mark completed items)
- Ensure all tests pass and documentation is updated

### Creating PRs via GitHub CLI

To avoid formatting issues in PR descriptions:

- Prefer `gh pr create --fill` to prefill title/body from the commit and apply the repo’s PR template
- If supplying a custom body, use `--body-file <file>` so newlines render correctly (avoid literal `\n`)

Example:

```bash
gh pr create \
  --base main \
  --head $(git branch --show-current) \
  --title "$(git log -1 --pretty=%s)" \
  --body-file .github/PULL_REQUEST_TEMPLATE.md
```

## Release Process

Merges to `main` may trigger automated CI/CD and GitOps processes for test environments. Actual stable releases are cut with SemVer tags, and `CHANGELOG.md` entries are updated accordingly.

Release artifacts typically include:
- Container images
- Deployment manifests
- Updated documentation
- Release notes in CHANGELOG.md

## Support and Contact

For questions or help, open an issue in the relevant repository. We encourage an open and collaborative environment. Feel free to propose improvements, features, or ask for clarification at any time.
