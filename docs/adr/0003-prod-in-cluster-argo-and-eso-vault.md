# ADR-0003: ENV=prod Uses In-Cluster Argo CD and ESO + Vault for Secrets

## Status
Accepted

## Context
We are enabling ENV=prod for the Bitiq GitOps stack on OpenShift Container Platform (OCP) 4.19. We must choose a management model for Argo CD (in-cluster per environment vs. central multi-cluster control) and a production-ready approach to secrets (manual, SealedSecrets, or externalized). We also need to ensure operator compatibility with OCP 4.19 and provide operational runbooks and preflight checks.

## Decision
1) Argo CD management model
- Use an in-cluster Argo CD per prod cluster by default.
- The ApplicationSet for `prod` uses `clusterServer=https://kubernetes.default.svc` so the umbrella and child Applications target the local cluster API.
- Document a central Argo option for future use (requires registering remote clusters, parameterizing destinations, and extra HA/capacity planning), but do not implement it now.

2) Secrets management
- Use External Secrets Operator (ESO) with HashiCorp Vault as the system of record for production secrets.
- Ship a Helm chart (`charts/eso-vault-examples`) enabled by default that renders a `ClusterSecretStore` and selected `ExternalSecret` resources:
  - `openshift-gitops/argocd-image-updater-secret`
  - `openshift-pipelines/quay-auth`
  - `openshift-pipelines/github-webhook-secret`
- Provide a dedicated runbook (`docs/PROD-SECRETS.md`) to install ESO, configure Vault (policy/role), and enable the chart.

3) Operator compatibility
- Pin OpenShift GitOps to channel `gitops-1.18` and OpenShift Pipelines to channel `pipelines-1.20`, per Red Hat compatibility matrices for OCP 4.19.

4) Operational guardrails
- Provide a production runbook (`docs/PROD-RUNBOOK.md`) and a preflight script (`scripts/prod-preflight.sh`) to validate cluster readiness (login, version, nodes, storage, DNS, catalogs) before bootstrap.
- Include Argo CD RBAC/SSO hardening and Tekton resource/permissions guidance.

## Consequences
Positive
- Stronger security boundaries: each cluster remains operationally isolated; no central credential sprawl.
- Simpler networking: no required egress from a central control plane to prod API servers.
- Secret rotation and audit via Vault; no sensitive data in Git.

Trade-offs
- Slightly higher operational overhead: Argo CD is upgraded per cluster.
- ESO/Vault becomes a runtime dependency; operators must provision and manage Vault access.
- Centralized fleet visibility is deferred; enabling central Argo later requires a controlled follow-on.

## Alternatives Considered
- Central Argo now: good for fleet-wide visibility and promotion, but increases blast radius and credential/network complexity for initial prod rollout.
- SealedSecrets only: keeps secrets in Git encrypted, but requires key management and lacks centralized rotation and audit.

## References
- Runbook: `docs/PROD-RUNBOOK.md`
- Secrets: `docs/PROD-SECRETS.md`, `charts/eso-vault-examples/`
- Preflight: `scripts/prod-preflight.sh`
- Operator channels: `charts/bootstrap-operators/values.yaml`
- ApplicationSet envs: `charts/argocd-apps/values.yaml`
