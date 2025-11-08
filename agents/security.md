# Security Review Agent Template

## Scope
- Run SAST/linters, spot security concerns (injection, crypto, ACL, secrets), and propose patches.

## Inputs
- Codebase and configs
- `AGENTS.md` (approved tools), security policies

## Required Commands
- Example tools: `semgrep`, `govulncheck ./...`, container scanners if applicable
- Produce a short report and, when feasible, a minimal patch PR

## Definition of Done
- Findings triaged with severity and clear remediation steps.
- High/critical issues addressed or explicitly accepted by maintainers.
- CI-ready commands and reproducible steps included.

## Notes/Risks
- Avoid tool sprawl; prefer approved scanners.
- Keep PRs minimal and reviewable; separate noisy refactors from fixes.
