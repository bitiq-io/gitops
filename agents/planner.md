# Planner Agent Template

## Scope
- Convert high-level issues or ideas into clear acceptance criteria and a scoped TODO list.
- Ensure alignment with SPEC/ADRs and lifecycle.

## Inputs
- `SPEC.md`, relevant ADRs (`docs/adr/`)
- Existing `TODO.md`
- Open issues/PRs

## Required Commands
- None mandatory. When code exists, prefer read-only planning; suggest verification commands for implementers.

## Definition of Done
- Drafted acceptance criteria are specific, testable, and in-scope for one repo.
- Proposed tasks follow Conventional Commits format and fit `project-management/todo-template.md`.
- Includes verification steps (commands or checks) for each task.

## Notes/Risks
- Avoid cross-repo coupling unless explicitly required and tracked.
- Defer prioritization to maintainers; provide rationale and dependencies.
