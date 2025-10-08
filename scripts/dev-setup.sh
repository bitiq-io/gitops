#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOOK_DIR="$ROOT_DIR/.git/hooks"
HOOK_FILE="$HOOK_DIR/commit-msg"

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
cat > "$HOOK_FILE" << 'EOF'
#!/usr/bin/env bash
# Enforce Conventional Commits locally before creating commits
npx --yes @commitlint/cli@18 --config commitlint.config.mjs --edit "$1"

# Guard against literal "\\n" sequences in commit messages (common when using -m "...\n...")
if grep -q '\\n' "$1"; then
  echo "Commit message contains literal \\n characters. Use 'git commit -F <file>' or a heredoc for multi-line messages." >&2
  exit 1
fi
EOF
chmod +x "$HOOK_FILE"

echo "Installed commit-msg hook: $HOOK_FILE"
echo "Conventional Commits will be validated locally on commit."
