#!/usr/bin/env bash
set -Eeuo pipefail
log(){ printf '[%s] %s\n' "$(date -Ins)" "$*"; }
log "Running helm lint on all charts…"
make lint
log "Rendering templates for each env…"
make template
log "OK"
