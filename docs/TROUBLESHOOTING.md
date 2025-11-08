Dev Vault and VSO/VCO Troubleshooting

Symptoms
- local-e2e-setup.sh appears to “hang” at: Creating namespace vault-dev
- vault-secrets-operator-controller-manager logs show DNS/connection errors:
  - lookup vault-dev.vault-dev.svc: no such host
  - connect: connection refused
  - Error making API request … auth/kubernetes/login: 403 permission denied

Root Causes and Fixes
- Image rewrite breaks direct pulls
  - What: On OpenShift, external image pulls can be rewritten to registry.connect.redhat.com. For images that don’t exist there (e.g., docker.io/hashicorp/vault:1.15.6), pods hit ImagePullBackOff.
  - Why it “hangs”: dev-vault.sh waits for the deployment rollout; during ImagePullBackOff this looks like a hang after the last log line (“Creating namespace vault-dev”).
  - Fix (short-term): Import the image into an ImageStream and patch the Deployment to use the internal registry reference. Example:
    - oc -n vault-dev import-image vault-dev:1.15.6 --from=docker.io/hashicorp/vault:1.15.6 --confirm
    - oc -n vault-dev set image deploy/vault-dev vault=image-registry.openshift-image-registry.svc:5000/vault-dev/vault-dev:1.15.6
  - Fix (long-term): dev-vault.sh now auto-detects OpenShift and attempts a bounded ImageStream import (15s) before falling back to the source image. It also rescues ImagePullBackOff by importing and patching automatically.

- VSO auth 403 permission denied
  - What: VSO logs “403 permission denied” when calling auth/kubernetes/login.
  - Why: The “gitops-local” Kubernetes auth role did not exist yet because dev-vault setup aborted before auth configuration (typically due to the image pull issue). VSO verified the JWT but the role was missing or constraints didn’t match.
  - Fix: Ensure dev-vault completes these steps:
    - Enable kubernetes auth and write auth/kubernetes/config with token_reviewer_jwt, kubernetes_host, kubernetes_ca_cert
    - Create policy gitops-local for gitops/data/*
    - Create role gitops-local bound to namespaces openshift-gitops, openshift-pipelines, bitiq-local

- VCO 403 on auth engine mount (AuthEngineMount)
  - What: Vault Config Operator logs 403 “permission denied” on PUT /v1/sys/auth/kubernetes/… while reconciling AuthEngineMount.
  - Why: The Vault policy used by VCO (role kube-auth) lacked permissions on sys/auth and sys/auth/*, so it could not enable or update the Kubernetes auth mount.
  - Fix (short-term): Update policy kube-auth to include:
    - path "sys/auth" { capabilities = ["read","update"] }
    - path "sys/auth/*" { capabilities = ["create","read","update","delete","list"] }
  - Fix (long-term): dev-vault.sh now writes kube-auth with these capabilities by default; re-run the helper or upgrade to the latest scripts.

What Changed (Why It’s Fixed)
- scripts/dev-vault.sh
  - Default behavior is now “auto”: on OpenShift, attempt ImageStream import with a short timeout; otherwise, use the source image. If rollout fails due to ImagePullBackOff, the script imports and patches the deployment, then retries the rollout.
- scripts/local-e2e-setup.sh
  - No longer forces DEV_VAULT_IMPORT=false. This avoids the OpenShift mirror rewrite pitfall in fresh clusters.

Verification Steps
- Run with FAST_PATH=true AUTO_DEV_VAULT=true on CRC:
  1) dev Vault should deploy successfully (deployment available)
  2) VSO should reconcile secrets:
     - openshift-gitops/argocd-image-updater-secret
     - openshift-pipelines/quay-auth
     - openshift-pipelines/github-webhook-secret

Notes
- If you must skip image import (e.g., egress is blocked), set DEV_VAULT_IMPORT=false explicitly, but expect to supply a reachable in-cluster image reference or add an ImageContentSourcePolicy mirror that hosts the required image.
  
