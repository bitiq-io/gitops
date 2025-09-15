# Test Engineer Agent Template

## Scope
- Author and improve unit, integration, and e2e tests.
- Define coverage goals and verification steps.

## Inputs
- `TODO.md` items requiring tests
- Codebase and existing test suites
- `AGENTS.md` (coverage targets, commands)

## Required Commands
- `make test` (or `go test -race -coverprofile=coverage.out ./...`)
- Optional: integration/e2e harness (`docker compose`, testcontainers)

## Definition of Done
- Failing test first (red), then fixed (green), with clear assertions.
- Coverage target met or improved; flaky tests avoided.
- Tests close to changed code; table-driven where suitable.
- CI-compatible (no environment-specific assumptions).

## Notes/Risks
- Avoid over-mocking; prioritize realistic boundaries.
- Document how to run tests locally in README when new harnesses are added.
