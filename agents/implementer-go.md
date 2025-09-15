# Feature Implementation (Go) Agent Template

## Scope
- Implement features and fixes in Go services with tests and observability.

## Inputs
- `TODO.md` task(s) with acceptance criteria
- Codebase, existing tests, configs
- `AGENTS.md`, `guides/golang-microservices.md`

## Required Commands
- `make build` (or `go build ./...`)
- `make test` (or `go test -race -coverprofile=coverage.out ./...`)
- `make lint` (or `golangci-lint run`)
- `govulncheck ./...` if configured

## Definition of Done
- All tests passing locally; added tests for new logic.
- Lint and vulnerability checks pass.
- Logging and OTEL spans added where appropriate.
- Docs updated where impacted (README/SPEC/ADR references).
- Commit message matches `TODO.md` entry (Conventional Commits).

## Notes/Risks
- Keep changes minimal and scoped; avoid unrelated refactors.
- Follow repo style; prefer table-driven tests.
