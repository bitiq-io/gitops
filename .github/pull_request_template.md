Title: <type(scope): short summary>

Summary
- What changed and why
- Environments affected: local|sno|prod (list)
- Charts/values touched: [paths]

Checklist
- [ ] No secrets, kubeconfigs, or tokens committed
- [ ] Follows image tag grammar and versioning rules (docs/CONVENTIONS.md)
- [ ] If umbrella impacted: composite appVersion updated and `make verify-release` passes
- [ ] Local validation completed: `make lint`, `make hu` (if applicable), `make template`, `make validate`, `make verify-release`
- [ ] PR is scoped to a single env (or exceptions explicitly justified)
- [ ] No operator channel/default changes, or explicit approval + references included
- [ ] Rollback path via Git unaffected (no in‑cluster edits)

Notes
- Links to related issues, runbooks (docs/ROLLBACK.md, docs/SNO-RUNBOOK.md), or references

