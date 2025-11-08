#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOOK_DIR="$ROOT_DIR/.git/hooks"
HOOK_COMMIT_MSG="$HOOK_DIR/commit-msg"
HOOK_PRE_COMMIT="$HOOK_DIR/pre-commit"
HOOK_PRE_PUSH="$HOOK_DIR/pre-push"

echo "Ensuring dev dependencies are installed (commitlint)…"
if command -v npm >/dev/null 2>&1; then
  if [ -f "$ROOT_DIR/package-lock.json" ]; then
    (cd "$ROOT_DIR" && npm ci --silent || npm ci)
  elif [ -f "$ROOT_DIR/package.json" ]; then
    (cd "$ROOT_DIR" && npm install --silent || npm install)
  else
    (
      cd "$ROOT_DIR"
      npm init -y >/dev/null 2>&1 || true
      npm install -D @commitlint/cli@^18 @commitlint/config-conventional@^18 --silent || \
      npm install -D @commitlint/cli@^18 @commitlint/config-conventional@^18
    )
  fi
else
  echo "npm not found; commitlint may use npx on-demand. Install Node/npm for local validation."
fi

mkdir -p "$HOOK_DIR"
cat > "$HOOK_COMMIT_MSG" << 'EOF'
#!/usr/bin/env bash
# Enforce Conventional Commits locally before creating commits
npx --yes @commitlint/cli@18 --config commitlint.config.mjs --edit "$1"

# Guard against literal "\\n" sequences in commit messages (common when using -m "...\n...")
if grep -q '\\n' "$1"; then
  echo "Commit message contains literal \\n characters. Use 'git commit -F <file>' or a heredoc for multi-line messages." >&2
  exit 1
fi
EOF
chmod +x "$HOOK_COMMIT_MSG"

echo "Installed commit-msg hook: $HOOK_COMMIT_MSG"
echo "Conventional Commits will be validated locally on commit."

# Ensure helm-unittest plugin exists for local validation
if command -v helm >/dev/null 2>&1; then
  if ! helm plugin list 2>/dev/null | grep -q 'unittest'; then
    echo "Installing helm-unittest plugin..."
    helm plugin install https://github.com/helm-unittest/helm-unittest >/dev/null 2>&1 || \
    helm plugin install https://github.com/helm-unittest/helm-unittest
  fi
else
  echo "helm not found; skipping helm-unittest plugin setup."
fi

# Pre-commit: quick local checks (lint + unit tests)
cat > "$HOOK_PRE_COMMIT" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)
cd "$ROOT_DIR"

# Allow opting out per-invocation
if [[ "${SKIP_PRECOMMIT:-}" == "1" ]]; then
  exit 0
fi

echo "[pre-commit] Running helm lint + unit tests…"
make lint >/dev/null
# Run unittest only if plugin is available
if helm plugin list 2>/dev/null | grep -q 'unittest'; then
  make hu >/dev/null
else
  echo "[pre-commit] helm-unittest plugin not found; skipping hu"
fi
EOF
chmod +x "$HOOK_PRE_COMMIT"
echo "Installed pre-commit hook: $HOOK_PRE_COMMIT"

# Pre-push: comprehensive validation and optional E2E smoke
cat > "$HOOK_PRE_PUSH" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)
cd "$ROOT_DIR"

# Allow opting out
if [[ "${SKIP_PREPUSH:-}" == "1" ]]; then
  exit 0
fi

echo "[pre-push] make validate…"
make validate >/dev/null

echo "[pre-push] verify release version alignment…"
make verify-release >/dev/null

# Optional E2E smoke (requires oc login + Quay creds and tools)
if [[ "${E2E_SMOKE:-}" == "1" ]]; then
  echo "[pre-push] Running updater E2E smoke…"
  bash scripts/e2e-updater-smoke.sh || {
    echo "[pre-push] E2E smoke failed" >&2
    exit 1
  }
fi
EOF
chmod +x "$HOOK_PRE_PUSH"
echo "Installed pre-push hook: $HOOK_PRE_PUSH"
