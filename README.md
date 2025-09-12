# gitops

Helm-first GitOps repo for running the same Argo CD + Tekton stack across OpenShift environments.

## Status & Links

- Version: `v0.1.0`
- Spec: [SPEC.md](SPEC.md)
- Tasks: [TODO.md](TODO.md)
- ADRs: [docs/adr/](docs/adr/)
- Changelog: [CHANGELOG.md](CHANGELOG.md)
- Security Policy: [SECURITY.md](SECURITY.md)
- Agents Guide: [AGENTS.md](AGENTS.md)

## Features

- Installs OpenShift GitOps (Argo CD) and OpenShift Pipelines (Tekton) via OLM.
- Uses an ApplicationSet with Helm `ignoreMissingValueFiles` to switch environments.
- Enables Argo CD Image Updater with Git write-back to Helm values.
- Provides a sample Helm app for end-to-end CI/CD.

## Architecture

- Charts for operators, umbrella app, image updater, pipelines, and sample app.
- Scripts for bootstrapping and validation.
- ADRs documenting decisions live in [docs/adr/](docs/adr/).

## Configuration

Set the target environment and base domain:

```bash
export ENV=local # or sno|prod
export BASE_DOMAIN=apps-crc.testing # required for sno|prod
```

## Testing

```bash
make lint
make template
```

## Security

- Follow the [Security Policy](SECURITY.md).
- Do not commit secrets; use SealedSecrets or External Secrets when available.

## Deployment

Bootstrap operators and GitOps apps:

```bash
./scripts/bootstrap.sh
```

## License & Maintainers

- License: TBD
- Maintainers: Bitiq ecosystem team
