# Production OCP (ENV=prod) Runbook

This runbook documents how to bootstrap the `gitops` repository onto a production-grade OpenShift Container Platform (OCP) 4.19 cluster using the in-cluster Argo CD model. It parallels the local and SNO flows so that `ENV=prod` reaches full CI/CD parity. Current component baselines (September 29, 2025): OCP 4.19, OpenShift GitOps 1.13+, OpenShift Pipelines 1.17+, Argo CD Image Updater v0.16.

## 1. Audience & Prerequisites

- **Use cases**: Staging or production OCP clusters that require GitOps-driven deployments with Tekton CI and automated image promotion.
- **Cluster requirements** (follow Red Hat production sizing guidance):
  - Minimum three control plane nodes and at least two worker nodes sized for your workloads.
  - Default storage class that supports ReadWriteOnce PVCs for Tekton pipelines and sample app state.
  - Wildcard DNS record for applications: `*.apps.<cluster-domain>` resolves to the ingress load balancer VIP.
  - Outbound connectivity to Git hosting, container registry (e.g., Quay.io), and Red Hat Operator Catalog sources.
- **Workstation**: `oc`, `helm` 3.14+, `git`, `make`, and this repository cloned.
- **Access**: Cluster-admin privileges on the target cluster; credentials to write to the Git repository and container registry.
- **Security**: Plan how you will manage secrets (SealedSecrets, External Secrets Operator (ESO), or manually via `oc`). Never commit secrets to Git.

## 2. Decide operator channels (GitOps & Pipelines)

OpenShift GitOps and OpenShift Pipelines are installed via `charts/bootstrap-operators`. The repo pins channels known to support OCP 4.19:

1. GitOps channel `gitops-1.18` (supports OCP 4.14, 4.16-4.19 per [GitOps 1.18 compatibility matrix][gitops-1-18]).
2. Pipelines channel `pipelines-1.20` (supports OCP 4.15-4.19 per [Pipelines 1.20 compatibility matrix][pipelines-1-20]).
3. If Red Hat publishes newer GA channels for OCP 4.19, update `charts/bootstrap-operators/values.yaml` accordingly and document the change in your PR (per `AGENTS.md`).

[gitops-1-18]: https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.18/html/release_notes/gitops-release-notes#GitOps-compatibility-support-matrix_gitops-release-notes
[pipelines-1-20]: https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/1.20/html/release_notes/op-release-notes-1-20#compatibility-support-matrix_op-release-notes

## 3. Cluster readiness checklist

1. **Login and verify nodes**
   ```bash
   oc login https://api.<cluster-domain>:6443 -u <admin>
   oc get nodes -o wide
   ```
   - Ensure all control plane and worker nodes report `Ready`.
2. **Default storage class**
   ```bash
   oc get storageclass
   ```
   - Mark the intended class as default if needed:
     ```bash
     oc annotate storageclass <name> storageclass.kubernetes.io/is-default-class="true"
     ```
3. **DNS & TLS**
   - Confirm a wildcard DNS entry exists: `*.apps.<cluster-domain>`.
   - If using custom certificates, ensure the ingress controller and your workstation trust the CA.
4. **Operator catalogs**
   - Confirm the `redhat-operators` source is available, or mirror it for disconnected installs.
   - For restricted networks, prepare ImageContentSourcePolicies and secrets ahead of time.

## 4. Clone the repo & export env vars

```bash
git clone https://github.com/<your-org>/gitops.git
cd gitops

export ENV=prod
export BASE_DOMAIN=apps.<cluster-domain>
export TARGET_REV=${TARGET_REV:-main}
export GIT_REPO_URL=${GIT_REPO_URL:-$(git remote get-url origin)}
```

- `BASE_DOMAIN` must match the wildcard DNS (e.g., `apps.ocp.prod.example`).
- `GIT_REPO_URL` should be your writable fork if Argo CD will push image updates.

## 5. Run the prod preflight

Use the accompanying script (added in this branch) to validate cluster prerequisites before bootstrapping.

```bash
./scripts/prod-preflight.sh
```

The preflight checks:
- `oc` login and API reachability.
- At least three Ready nodes (control plane) and two Ready worker nodes.
- Default storage class present.
- `BASE_DOMAIN` exported and wildcard DNS resolves.
- Operator catalog sources accessible.
- Reminder to review operator channels and secret management strategy.

Resolve any failures before continuing.

## 6. Bootstrap the GitOps stack (ENV=prod)

```bash
ENV=prod BASE_DOMAIN="$BASE_DOMAIN" TARGET_REV="$TARGET_REV" GIT_REPO_URL="$GIT_REPO_URL" \
  ./scripts/bootstrap.sh
```

What happens:
1. Installs (or ensures) OpenShift GitOps and OpenShift Pipelines via `charts/bootstrap-operators` in `openshift-operators`.
2. Waits for the default Argo CD instance in `openshift-gitops`.
3. Deploys the `bitiq-umbrella-by-env` ApplicationSet with `envFilter=prod` and `baseDomainOverride=$BASE_DOMAIN`.
4. Renders a single `bitiq-umbrella-prod` Application whose child Applications deploy in-cluster (`https://kubernetes.default.svc`) to the `bitiq-prod` namespace.

Monitor the Application:
```bash
oc -n openshift-gitops get application bitiq-umbrella-prod -w
```

After sync, confirm namespaces and routes:
```bash
oc get ns | grep bitiq-
oc -n bitiq-prod get routes
```

## 7. Configure production secrets & credentials

Production workloads should manage secrets via sealed or externalized workflows. Options:

1. **Argo CD repo credentials (write access)**
   - Prefer a dedicated robot account or deploy key limited to this repo.
   - Store credentials via SealedSecrets/ESO in `openshift-gitops`, or manually add with `argocd repo add`.

2. **Argo CD Image Updater token**
   - Create a dedicated Argo CD account with `apiKey` capability and `role:admin` scoped to the project.
   - Manage the token as a SealedSecret or ESO Secret (`argocd-image-updater-secret` containing `argocd.token`).
   - Update `imageUpdater.pullSecret` if you use private registries.

3. **Container registry push credentials**
   - For Quay.io:
     ```bash
     oc -n openshift-pipelines create secret docker-registry quay-auth \
       --docker-server=quay.io \
       --docker-username=<robot-user> \
       --docker-password=<token> \
       --docker-email=<email>
     oc -n openshift-pipelines annotate secret quay-auth tekton.dev/docker-0=https://quay.io --overwrite
     oc -n openshift-pipelines secrets link pipeline quay-auth --for=pull,mount
     ```
   - Replace with your internal registry if pushing to OpenShift’s integrated registry.

4. **GitHub webhook secret for Tekton triggers**
   ```bash
   oc -n openshift-pipelines create secret generic github-webhook-secret \
     --from-literal=secretToken='<random value>'
   ```
   - Point your repo webhook to the listener route once created (`oc -n openshift-pipelines get route el-bitiq-listener`).

5. **Certificate and TLS secrets**
   - If you terminate TLS with custom certificates, ensure they are distributed to the ingress controller or Routes via annotations.

Document each secret’s source-of-truth in your operations runbook.

## 8. Validate the deployment

1. **Local chart validation**
   ```bash
   make lint
   make template
   make validate
   ```

2. **Cluster smoke tests**
   ```bash
   make smoke ENV=prod BASE_DOMAIN="$BASE_DOMAIN"
   ```
   - Optionally run `./scripts/smoke-image-update.sh` to tail Image Updater logs.

3. **Tekton pipelines**
   - Push a code or tag change to the sample repositories (`toy-service`, `toy-web`).
   - Verify PipelineRuns succeed:
     ```bash
     oc -n openshift-pipelines get pipelineruns -w
     ```
   - Confirm new image tags reach the `bitiq-prod` namespace and the sample app Routes serve updated content.

4. **Image Updater**
   ```bash
   oc -n openshift-gitops logs deploy/argocd-image-updater --since=10m | grep -E 'Committing|Pushed change'
   ```
   - Ensure commits land in `charts/bitiq-sample-app/values-prod.yaml` on the tracked branch.

## 9. Operations & troubleshooting

- **Namespace or permission errors**: Confirm Argo CD has permission in `bitiq-prod` and `openshift-pipelines` (cluster-admin handles this by default).
- **Routes unreachable**: Check ingress controller status, wildcard DNS, and firewall rules.
- **Pipeline image pushes fail**: Validate registry credentials and that the service account has the `system:image-pusher` role for the target namespace.
- **Image Updater push errors**: Ensure Git credentials have write access and that the token is not expired.
- **Operator upgrades**: Coordinate GitOps/Pipelines operator channel bumps; test in staging first.
- **Disaster recovery**: Follow `docs/ROLLBACK.md` for Git-driven rollbacks; avoid manual cluster edits.

## 10. Advanced: Central Argo CD (documentation only)

If you later choose to manage prod from a central Argo CD instance:
- Register the prod cluster with `argocd cluster add` and store credentials securely (consider ESO/SealedSecrets).
- Update `charts/argocd-apps/values.yaml` to set `prod.clusterServer` to the external API URL.
- Parameterize nested Application destinations to target the remote cluster, and ensure the control cluster hosts all CRDs (Application, ApplicationSet).
- Plan for HA and capacity: increase repo-server and application-controller resources, and monitor sync concurrency.
- Revisit network policies to allow outbound gRPC/HTTPS from the central cluster to prod.

No chart changes for central Argo are included in this branch; treat this section as future guidance only.

## 11. References (September 2025)

- OCP 4.19 docs: https://docs.redhat.com/en/documentation/openshift_container_platform/4.19
- OpenShift GitOps documentation: https://docs.openshift.com/gitops/latest/
- OpenShift Pipelines 1.17 docs: https://docs.openshift.com/pipelines/1.17/
- Argo CD Image Updater: https://argocd-image-updater.readthedocs.io/en/stable/
- SealedSecrets: https://sealed-secrets.netlify.app/
- External Secrets Operator: https://external-secrets.io/latest/
