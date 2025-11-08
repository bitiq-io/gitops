# Architect & API Design Agent Template

## Scope
- Propose service boundaries, APIs (gRPC/OpenAPI), and request flows.
- Produce initial contracts, diagrams, and contract tests.

## Inputs
- `SPEC.md`, relevant ADRs (`docs/adr/`)
- Existing API definitions (`api/grpc/proto`, `api/rest/openapi`) if present
- `guides/golang-microservices.md`

## Required Commands
- If applicable: code generation checks (`make generate` or `protoc`/`oapi-codegen`)
- Validate contracts compile and pass basic linters

## Definition of Done
- Non-breaking within a major version, or ADR prepared for breaking changes.
- Contracts + minimal contract tests added.
- Docs updated (README/API docs) and references added.

## Notes/Risks
- Flag irreversible schema decisions and trade-offs in an ADR draft.
