# TODO - [Service Name]

> This document tracks pending development tasks for the [Service Name] microservice. 
> Tasks are formatted to align with Conventional Commits standards to streamline the workflow 
> between planning, implementation, and changelog generation.
>
> **Automation-Friendly Workflow:**
> - TODO.md contains ONLY pending tasks (no completed items)
> - Each task is formatted to be directly usable as a commit message
> - When completing a task, use its description as your commit message, then remove it from TODO.md
> - CHANGELOG.md will be automatically generated from commit history
> 
> **Task Format Requirements:**
> - Begin with type and scope: `type(scope): description` 
> - For breaking changes, add `!` after the scope: `feat(api)!: description`
> - Reference issue numbers at the end of the description (#123)
> - Keep descriptions clear and concise (suitable for a commit message)
> - Group by Conventional Commits categories

## Next Release Tasks

### feat: Features

> New features and functionality

- feat(api): implement user authentication endpoint (#issue-number)
- feat(core): add event validation middleware (#issue-number)
- feat(db): create initial Couchbase connection manager (#issue-number)

### fix: Bug Fixes

> Bug fixes and error corrections

- fix(api): correct error response format in REST endpoints (#issue-number)
- fix(security): resolve JWT validation vulnerability (#issue-number)

### docs: Documentation

> Documentation changes

- docs(readme): update with new configuration options (#issue-number)
- docs(api): add comprehensive API examples (#issue-number)

### style: Code Style

> Code style and formatting changes

- style(global): enforce consistent code formatting throughout codebase (#issue-number)
- style(api): standardize error response structures (#issue-number)

### refactor: Code Refactoring

> Code changes that neither fix bugs nor add features

- refactor(core): simplify event processing pipeline (#issue-number)
- refactor(api): reorganize middleware chain for better clarity (#issue-number)

### perf: Performance

> Performance improvements

- perf(db): optimize query patterns for event retrieval (#issue-number)
- perf(api): implement response caching for high-traffic endpoints (#issue-number)

### test: Tests

> Adding or modifying tests

- test(unit): add tests for event validation logic (#issue-number)
- test(integration): create Couchbase repository tests (#issue-number)
- test(e2e): implement critical user flow tests (#issue-number)

### build: Build System

> Changes to build process or tools

- build(make): add new build targets for production deployment (#issue-number)
- build(docker): optimize Dockerfile for smaller image size (#issue-number)

### ci: Continuous Integration

> Changes to CI configuration

- ci(pipeline): configure Tekton pipeline for automated testing (#issue-number)
- ci(actions): set up GitHub Actions for PR validation (#issue-number)

### chore: Maintenance

> Other changes that don't modify src or test files

- chore(deps): update dependencies to latest versions (#issue-number)
- chore(gitignore): add new build artifacts to ignore list (#issue-number)

---

> **Suggested Automation:**
> - A pre-commit hook could validate that commit messages match TODO items
> - A post-commit hook could automatically remove the committed task from TODO.md
> - A release script could generate CHANGELOG.md entries from commits since last release
> - Consider using tools like `git-cliff` or `conventional-changelog` to automate changelog generation