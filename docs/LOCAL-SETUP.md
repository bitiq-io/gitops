Local setup on macOS (OpenShift Local)

Prereqs
- Tools: install `helm`, `oc`, `argocd`.
  - Homebrew: `brew install helm openshift-cli argocd`
- OpenShift Local (CRC): install from Red Hat (or `brew install crc`).
- Resources: 4+ CPUs, 12–16 GiB RAM, 35+ GiB free disk.

Start OpenShift Local
- Configure resources:
  - `crc config set memory 12288`
  - `crc config set cpus 4`
- Start cluster:
  - `crc setup && crc start`
  - `eval $(crc oc-env)`
- Login to the cluster:
  - `oc login -u kubeadmin -p $(crc console --credentials | awk '/kubeadmin/ {print $2}')`

Bootstrap this repo
- Clone your fork and ensure `origin` points to it.
- From the repo root:
  - `export ENV=local`
  - `./scripts/bootstrap.sh`
- This installs the GitOps and Pipelines operators and creates an ApplicationSet that renders one umbrella app for `local`.

Argo CD access and token for Image Updater
- Get the Argo CD host:
  - `ARGOCD_HOST=$(oc -n openshift-gitops get route openshift-gitops-server -o jsonpath='{.spec.host}')`
- Open the UI and log in via OAuth:
  - `open https://$ARGOCD_HOST` (or paste in browser)

Grant RBAC so kubeadmin can create tokens (once per cluster)
- Patch RBAC ConfigMap:
  - `oc -n openshift-gitops patch cm argocd-rbac-cm --type merge -p $'{"data":{"policy.csv":"g, system:cluster-admins, role:admin\ng, kubeadmin, role:admin\n","policy.default":"role:readonly"}}'`
- Restart Argo CD server:
  - `oc -n openshift-gitops rollout restart deploy/openshift-gitops-server`

Generate an Argo CD API token
- CLI (SSO):
  - `argocd login "$ARGOCD_HOST" --sso --grpc-web --insecure`
  - `TOKEN=$(argocd account generate-token --grpc-web)`
- Or UI: user menu → Generate token → copy value.

Provide the token to Image Updater (kept out of Git)
- Patch the Application to pass the Helm parameter:
  - `oc -n openshift-gitops patch application image-updater-${ENV} --type merge -p '{"spec":{"source":{"helm":{"parameters":[{"name":"argocd.token","value":"'"$TOKEN"'"}]}}}}'`
- Verify Secret created:
  - `oc -n openshift-gitops get secret argocd-image-updater-secret -o jsonpath='{.data.argocd\.token}' | base64 -d; echo`

Configure Argo CD repo write access
- CLI (recommended for OpenShift GitOps):

  ```bash
  export ARGOCD_SERVER=$(oc -n openshift-gitops get route openshift-gitops-server -o jsonpath='{.spec.host}')
  argocd login "$ARGOCD_SERVER" --sso --grpc-web

  # Fine-grained PAT with Contents:Read/Write, SSO-authorized for bitiq-io org
  export GH_PAT=<your_token>
  argocd repo add https://github.com/bitiq-io/gitops.git \
    --username <github-username> \
    --password "$GH_PAT" --grpc-web
  ```

- Sanity checks (either call should flip the PAT to “Last used …” in GitHub):

  ```bash
  curl -sS https://api.github.com/repos/bitiq-io/gitops \
    -H "Authorization: Bearer $GH_PAT" \
    -H "X-GitHub-Api-Version: 2022-11-28" | head -n 5

  git ls-remote https://<github-username>:$GH_PAT@github.com/bitiq-io/gitops.git | head
  ```

- UI alternative: Settings → Repositories → CONNECT REPO → HTTPS. Ensure the PAT (or SSH key) is authorized for the bitiq-io org.
- Image Updater uses Argo CD’s repo creds to commit Helm value changes, so the credential must have write access.

Sample app image
- Default image `quay.io/yourorg/bitiq-svc-api:0.1.0` is a placeholder.
- Either push a real image that:
  - Listens on port 8080
  - Responds to `/healthz`
- Or edit `charts/bitiq-sample-app/values-common.yaml` to point to a public image and/or adjust the probes/port in the template.

Tekton pipeline (optional)
- Default pushes to the in-cluster registry namespace `bitiq-ci`.
- Create namespace and allow pipeline SA to push:
  - `oc new-project bitiq-ci || true`
  - `oc policy add-role-to-user system:image-pusher system:serviceaccount:openshift-pipelines:pipeline -n bitiq-ci`
- Webhook: the `EventListener` has a Route. Set the secret in `charts/ci-pipelines/values.yaml` and point a GitHub webhook to it.

Validate and inspect
- Lint and template:
  - `make lint`
  - `make template`
- Watch applications:
  - `oc -n openshift-gitops get applications,applicationsets`
- Get sample app route and test:
  - `oc -n bitiq-local get route bitiq-sample-app -o jsonpath='{.spec.host}{"\n"}'`
  - `curl -k https://svc-api.apps-crc.testing/healthz` (adjust if you changed domain/image)

Troubleshooting
- Lint issues: run `helm lint charts/bitiq-sample-app -f charts/bitiq-sample-app/values-common.yaml -f charts/bitiq-sample-app/values-local.yaml`.
- RBAC errors generating token: ensure `argocd-rbac-cm` has `g, kubeadmin, role:admin` and server is restarted.
- Image pull errors: confirm image exists and is pullable from the cluster, and ports/probes match.
