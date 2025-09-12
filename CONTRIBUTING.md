# Contributing

## Commit conventions

All commits in this repository must follow the [Conventional Commits](https://www.conventionalcommits.org/) specification to ensure clarity and automated tooling support.

## TODO traceability

When adding TODO items in code or documentation, include a unique TODO ID and reference the commit and pull request where the follow-up is addressed. This practice provides traceability and context for future contributors. Example:

```yaml
# TODO: TODO-42 replace placeholder with actual values (see commit abc1234, PR #56)
```

When completing a TODO, reference the TODO ID in the commit message:

```
feat(chart): implement actual values (refs TODO-42)
```

This links the TODO comment, the commit that resolves it, and the associated PR for full traceability.
