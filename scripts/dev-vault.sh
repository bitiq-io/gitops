#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[%s] %s\n' "$(date -Ins)" "$*"; }
fatal() { log "FATAL: $*"; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || fatal "'$1' not found in PATH"
}

ACTION=${1:-up}
DEV_NAMESPACE=${DEV_VAULT_NAMESPACE:-vault-dev}
ESO_NAMESPACE=${ESO_NAMESPACE:-external-secrets-operator}
VAULT_RELEASE_NAME=${VAULT_RELEASE_NAME:-vault-dev}
HELM_RELEASE=${ESO_RELEASE_NAME:-eso-vault-examples}
USE_VAULT_OPERATORS=${VAULT_OPERATORS:-false}
# Allow overriding the dev Vault image; default to upstream Docker Hub
DEV_VAULT_IMAGE=${DEV_VAULT_IMAGE:-hashicorp/vault:1.15.6}

require oc
require helm

oc whoami >/dev/null 2>&1 || fatal "oc not logged in"

KUBE_HOST=$(oc whoami --show-server)

render_manifests() {
  cat <<'YAML'
apiVersion: v1
kind: Namespace
metadata:
  name: {{DEV_NAMESPACE}}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{VAULT_RELEASE_NAME}}
  namespace: {{DEV_NAMESPACE}}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: {{VAULT_RELEASE_NAME}}-tokenreview
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: {{VAULT_RELEASE_NAME}}
    namespace: {{DEV_NAMESPACE}}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{VAULT_RELEASE_NAME}}
  namespace: {{DEV_NAMESPACE}}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: {{VAULT_RELEASE_NAME}}
  template:
    metadata:
      labels:
        app: {{VAULT_RELEASE_NAME}}
    spec:
      serviceAccountName: {{VAULT_RELEASE_NAME}}
      containers:
        - name: vault
          image: {{VAULT_IMAGE}}
          args:
            - "server"
            - "-dev"
            - "-dev-root-token-id=root"
            - "-dev-listen-address=0.0.0.0:8200"
          ports:
            - name: http
              containerPort: 8200
          readinessProbe:
            httpGet:
              path: /v1/sys/health
              port: 8200
            initialDelaySeconds: 2
            periodSeconds: 5
          env:
            - name: VAULT_DEV_LISTEN_ADDRESS
              value: 0.0.0.0:8200
            # OpenShift Restricted SCC blocks setcap; skip it to avoid crashloops
            - name: SKIP_SETCAP
              value: "true"
            # Ensure Vault doesn't attempt mlock; safe for dev mode
            - name: VAULT_DISABLE_MLOCK
              value: "true"
            # Vault dev writes ~/.vault-token; ensure writable HOME
            - name: HOME
              value: /tmp
---
apiVersion: v1
kind: Service
metadata:
  name: {{VAULT_RELEASE_NAME}}
  namespace: {{DEV_NAMESPACE}}
spec:
  selector:
    app: {{VAULT_RELEASE_NAME}}
  ports:
    - name: http
      port: 8200
      targetPort: 8200
YAML
}

apply_manifests() {
  log "Deploying dev Vault in namespace ${DEV_NAMESPACE}"
  # Import image into an ImageStream to avoid node-side registry mirror rewrites
  local src_image tag image_for_deploy
  src_image="${DEV_VAULT_IMAGE}"
  tag="${src_image##*:}"
  if [[ "${tag}" == "${src_image}" ]] || [[ "${src_image}" == *"@"* ]] || [[ "${src_image}" == *"@sha256:"* ]]; then
    tag="latest"
  fi
  # Create imagestream and try to import the source image (best-effort)
  oc -n "${DEV_NAMESPACE}" apply -f - >/dev/null 2>&1 || true <<EOF
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: ${VAULT_RELEASE_NAME}
EOF
  if oc -n "${DEV_NAMESPACE}" import-image "${VAULT_RELEASE_NAME}:${tag}" --from="${src_image}" --confirm >/dev/null 2>&1; then
    image_for_deploy="image-registry.openshift-image-registry.svc:5000/${DEV_NAMESPACE}/${VAULT_RELEASE_NAME}:${tag}"
    log "Imported ${src_image} into ImageStream ${DEV_NAMESPACE}/${VAULT_RELEASE_NAME}:${tag}"
  else
    image_for_deploy="${src_image}"
    log "WARNING: Failed to import ${src_image}. Falling back to using it directly."
  fi
  render_manifests | sed \
    -e "s/{{DEV_NAMESPACE}}/${DEV_NAMESPACE}/g" \
    -e "s/{{VAULT_RELEASE_NAME}}/${VAULT_RELEASE_NAME}/g" \
    -e "s#{{VAULT_IMAGE}}#${image_for_deploy}#g" \
    | oc apply -f -
}

ensure_kv_mount() {
  # Ensure a KV v2 mount exists at path "gitops"
  log "Ensuring KV v2 mount exists at path 'gitops'"
  oc -n "${DEV_NAMESPACE}" exec deploy/"${VAULT_RELEASE_NAME}" -- \
    sh -c "
      set -euo pipefail
      export VAULT_ADDR=\"http://127.0.0.1:8200\"
      export VAULT_TOKEN=\"root\"
      if ! vault secrets list -format=json | grep -q '"gitops/"'; then
        vault secrets enable -path=gitops -version=2 kv >/dev/null
      fi
    "
}

wait_for_deployment() {
  local dep=$1 ns=$2
  log "Waiting for deployment/${dep} in ${ns} to become available…"
  oc -n "${ns}" rollout status deploy/"${dep}" --timeout=180s
}

configure_kubernetes_auth() {
  log "Configuring Vault Kubernetes auth + policies"
  oc -n "${DEV_NAMESPACE}" exec deploy/"${VAULT_RELEASE_NAME}" -- \
    sh -c "
      set -euo pipefail
      export VAULT_ADDR=\"http://127.0.0.1:8200\"
      export VAULT_TOKEN=\"root\"
      vault auth enable kubernetes >/dev/null 2>&1 || true
      vault write auth/kubernetes/config \
        token_reviewer_jwt=\"\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)\" \
        kubernetes_host=\"${KUBE_HOST}\" \
        kubernetes_ca_cert=\"\$(cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt)\" >/dev/null
      vault policy write gitops-prod - <<'HCL'
      path \"gitops/data/*\" {
        capabilities = [\"create\", \"read\", \"update\", \"list\"]
      }
HCL
      vault write auth/kubernetes/role/gitops-prod \
        bound_service_account_names=\"*\" \
        bound_service_account_namespaces=\"openshift-gitops,openshift-pipelines,bitiq-local\" \
        policies=\"gitops-prod\" \
        ttl=\"1h\" >/dev/null
      # VCO control-plane auth: allow managing k8s auth roles
      vault policy write kube-auth - <<'HCL'
      path \"auth/kubernetes/role/*\" {
        capabilities = [\"create\", \"read\", \"update\", \"delete\", \"list\"]
      }
      path \"auth/kubernetes/config\" {
        capabilities = [\"read\", \"update\"]
      }
      path \"auth/role/*\" {
        capabilities = [\"read\", \"list\"]
      }
      path \"sys/mounts\" { capabilities = [\"read\"] }
      path \"sys/auth\" { capabilities = [\"read\"] }
      path \"sys/policies/acl\" { capabilities = [\"read\", \"list\"] }
HCL
      vault write auth/kubernetes/role/kube-auth \
        bound_service_account_names=\"default\" \
        bound_service_account_namespaces=\"openshift-gitops\" \
        policies=\"kube-auth\" \
        ttl=\"1h\" >/dev/null
    "
}

seed_secrets() {
  # Prefer user-provided env vars; fall back to demo placeholders
  local argocd_token webhook_secret docker_json
  argocd_token="${ARGOCD_TOKEN:-local-argocd-token}"
  webhook_secret="${GITHUB_WEBHOOK_SECRET:-local-webhook-secret}"

  if [[ -n "${QUAY_DOCKERCONFIGJSON:-}" ]]; then
    docker_json="${QUAY_DOCKERCONFIGJSON}"
  elif [[ -n "${QUAY_USERNAME:-}" && -n "${QUAY_PASSWORD:-}" ]]; then
    # Cross-platform base64 (no wrap)
    local auth_b64
    auth_b64=$(printf '%s' "${QUAY_USERNAME}:${QUAY_PASSWORD}" | base64 | tr -d '\n')
    docker_json=$(printf '{"auths":{"quay.io":{"auth":"%s","email":"%s"}}}' \
      "$auth_b64" "${QUAY_EMAIL:-you@example.com}")
  else
    # demo:demo base64
    local demo_b64
    demo_b64=$(printf 'demo:demo' | base64 | tr -d '\n')
    docker_json=$(printf '{"auths":{"quay.io":{"auth":"%s"}}}' "$demo_b64")
  fi

  # Escape for inclusion in a double-quoted shell here-string
  local docker_json_esc
  docker_json_esc=$(printf '%s' "$docker_json" | sed -e 's/[\\"]/\\&/g')

  log "Seeding secrets into Vault KV path gitops/data/* (using provided env overrides when set)"
  oc -n "${DEV_NAMESPACE}" exec deploy/"${VAULT_RELEASE_NAME}" -- \
    sh -c "
      set -euo pipefail
      export VAULT_ADDR=\"http://127.0.0.1:8200\"
      export VAULT_TOKEN=\"root\"
      vault kv put gitops/argocd/image-updater token=\"${argocd_token}\" argocd.token=\"${argocd_token}\" >/dev/null
      vault kv put gitops/registry/quay dockerconfigjson=\"${docker_json_esc}\" .dockerconfigjson=\"${docker_json_esc}\" >/dev/null
      vault kv put gitops/github/webhook token=\"${webhook_secret}\" secretToken=\"${webhook_secret}\" >/dev/null
      vault kv put gitops/services/toy-service/config FAKE_SECRET=\"LOCAL_FAKE_SECRET\" >/dev/null
      vault kv put gitops/services/toy-web/config API_BASE_URL=\"https://toy-service.bitiq-local.svc.cluster.local\" >/dev/null
    "
}

install_eso_chart() {
  log "Ensuring vault-auth ServiceAccount exists in openshift-gitops"
  oc -n openshift-gitops create sa vault-auth >/dev/null 2>&1 || true

  log "Installing eso-vault-examples chart with dev Vault overrides"
  helm upgrade --install "${HELM_RELEASE}" charts/eso-vault-examples \
    --namespace "${ESO_NAMESPACE}" \
    --create-namespace \
    --set enabled=true \
    --set secretStore.enabled=true \
    --set secretStore.name=vault-global \
    --set-string secretStore.provider.vault.server="http://${VAULT_RELEASE_NAME}.${DEV_NAMESPACE}.svc:8200" \
    --set secretStore.provider.vault.auth.role=gitops-prod \
    --set secretStore.provider.vault.auth.serviceAccountRef.name=vault-auth \
    --set secretStore.provider.vault.auth.serviceAccountRef.namespace=openshift-gitops \
    --set argocdToken.enabled=true \
    --set quayCredentials.enabled=true \
    --set webhookSecret.enabled=true \
    --set toyServiceConfig.enabled=true \
    --set toyWebConfig.enabled=true
}

install_vso_runtime_chart() {
  local runtime_release=${VSO_RUNTIME_RELEASE_NAME:-vault-runtime}
  local addr="http://${VAULT_RELEASE_NAME}.${DEV_NAMESPACE}.svc:8200"
  log "Installing VSO runtime chart pointing at ${addr}"
  helm upgrade --install "${runtime_release}" charts/vault-runtime \
    --namespace openshift-gitops \
    --set enabled=true \
    --set-string vault.address="${addr}" \
    --set vault.kubernetesMount=kubernetes \
    --set vault.roleName=gitops-prod \
    --set-string namespaces.gitops=openshift-gitops \
    --set-string namespaces.pipelines=openshift-pipelines \
    --set-string namespaces.app=bitiq-local
}

ensure_crds() {
  local crd=$1
  log "Waiting for CRD ${crd}"
  for _ in {1..60}; do
    oc get crd "${crd}" >/dev/null 2>&1 && return 0
    sleep 2
  done
  fatal "Timed out waiting for CRD ${crd}"
}

wait_for_csv() {
  local ns=$1 sub=$2
  log "Waiting for Subscription ${sub} in ${ns} to report a current CSV…"
  local current=""
  for _ in {1..120}; do
    current=$(oc -n "${ns}" get subscription "${sub}" -o jsonpath='{.status.currentCSV}' 2>/dev/null || true)
    if [[ -n "${current}" ]]; then
      local phase
      phase=$(oc -n "${ns}" get csv "${current}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
      if [[ "${phase}" == "Succeeded" ]]; then
        log "Subscription ${sub} -> CSV ${current} is Succeeded"
        return 0
      fi
    fi
    sleep 5
  done
  fatal "Timed out waiting for CSV via Subscription ${sub}"
}

wait_for_secret() {
  local ns=$1 name=$2 timeout=${3:-180}
  log "Waiting for Secret ${ns}/${name}"
  for _ in $(seq 1 $((timeout/3))); do
    oc -n "$ns" get secret "$name" >/dev/null 2>&1 && return 0
    sleep 3
  done
  log "WARNING: Secret ${ns}/${name} not found within ${timeout}s"
  return 1
}

case "${ACTION}" in
  up)
    apply_manifests
    wait_for_deployment "${VAULT_RELEASE_NAME}" "${DEV_NAMESPACE}"
    ensure_kv_mount
    configure_kubernetes_auth
    seed_secrets
    if [[ "${USE_VAULT_OPERATORS}" == "true" ]]; then
      log "VAULT_OPERATORS=true: using VSO runtime instead of ESO"
      # Best-effort uninstall legacy ESO chart to avoid dual-writer in local
      helm -n "${ESO_NAMESPACE}" uninstall "${HELM_RELEASE}" >/dev/null 2>&1 || true
      # Ensure VSO CRDs
      ensure_crds vaultconnections.secrets.hashicorp.com
      ensure_crds vaultauths.secrets.hashicorp.com
      ensure_crds vaultstaticsecrets.secrets.hashicorp.com
      install_vso_runtime_chart
      # Wait for VSO-managed Secrets to appear
      wait_for_secret openshift-gitops argocd-image-updater-secret 240 || true
      wait_for_secret openshift-pipelines quay-auth 240 || true
      wait_for_secret openshift-pipelines github-webhook-secret 240 || true
      # Local conveniences
      if oc -n openshift-pipelines get sa pipeline >/dev/null 2>&1 && \
         oc -n openshift-pipelines get secret quay-auth >/dev/null 2>&1; then
        oc -n openshift-pipelines secrets link pipeline quay-auth --for=pull,mount >/dev/null 2>&1 || true
        log "Linked quay-auth to SA 'pipeline' in openshift-pipelines"
      fi
      if oc -n openshift-gitops get deploy/argocd-image-updater >/dev/null 2>&1; then
        oc -n openshift-gitops rollout restart deploy/argocd-image-updater >/dev/null 2>&1 || true
        log "Restarted argocd-image-updater deployment to pick up token"
      fi
      log "Dev Vault + VSO secrets ready."
    else
      install_eso_chart
      if oc -n "${ESO_NAMESPACE}" get subscription external-secrets-operator >/dev/null 2>&1; then
        wait_for_csv "${ESO_NAMESPACE}" "external-secrets-operator"
      else
        log "Subscription external-secrets-operator not found in ${ESO_NAMESPACE}; skipping CSV wait (ensure bootstrap installed ESO)."
      fi
      ensure_crds externalsecrets.external-secrets.io
      ensure_crds clustersecretstores.external-secrets.io
      # Wait for ESO-managed Secrets to reconcile, then perform local conveniences
      wait_for_secret openshift-gitops argocd-image-updater-secret 240 || true
      wait_for_secret openshift-pipelines quay-auth 240 || true
      wait_for_secret openshift-pipelines github-webhook-secret 240 || true
      # Link quay-auth to Tekton SA (idempotent, local-only convenience)
      if oc -n openshift-pipelines get sa pipeline >/dev/null 2>&1 && \
         oc -n openshift-pipelines get secret quay-auth >/dev/null 2>&1; then
        oc -n openshift-pipelines secrets link pipeline quay-auth --for=pull,mount >/dev/null 2>&1 || true
        log "Linked quay-auth to SA 'pipeline' in openshift-pipelines"
      fi
      # Restart Image Updater to pick up token changes
      if oc -n openshift-gitops get deploy/argocd-image-updater >/dev/null 2>&1; then
        oc -n openshift-gitops rollout restart deploy/argocd-image-updater >/dev/null 2>&1 || true
        log "Restarted argocd-image-updater deployment to pick up token"
      fi
      log "Dev Vault + ESO secrets ready."
    fi
    ;;
  down)
    log "Removing dev Vault resources"
    oc delete namespace "${DEV_NAMESPACE}" --ignore-not-found
    log "Deleting eso-vault-examples release (if present)"
    helm -n "${ESO_NAMESPACE}" uninstall "${HELM_RELEASE}" >/dev/null 2>&1 || true
    ;;
  *)
    fatal "Unknown action '${ACTION}'. Use up or down."
    ;;
esac
