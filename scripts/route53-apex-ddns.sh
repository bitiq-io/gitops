#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage: route53-apex-ddns.sh [--dry-run] [--zones-file PATH] [--wan-ip IPv4] [--skip-current-lookup]

Updates Route 53 apex A records to the current WAN IPv4.
Domains and hosted zone IDs are defined in the ZONES map below.

Options:
  --dry-run, -n   Print intended changes without calling Route 53
  --zones-file, -f PATH
                  Load domain→hostedZoneID mappings from file (overrides built-ins).
                  Accepted line formats (comments starting with # are ignored):
                    cyphai.com=Z123...
                    neuance.net Z456...
                    paulcapestany.com,Z789...
  --wan-ip, -w IPv4
                  Override detected WAN IPv4 (testing/CI). Env: ROUTE53_DDNS_WAN_IP
  --skip-current-lookup
                  Do not read current A records from Route 53 or DNS (CI/offline). Env: ROUTE53_DDNS_SKIP_LOOKUP
USAGE
}

log() { printf '[route53-ddns] %s\n' "$*"; }
err() { printf '[route53-ddns] ERROR: %s\n' "$*" >&2; }

# Debug tracing (enable with ROUTE53_DDNS_DEBUG=true|1|yes|on)
enable_debug() {
  if [[ "${ROUTE53_DDNS_DEBUG:-}" =~ ^(1|true|yes|on)$ ]]; then
    PS4='+ [${BASH_SOURCE##*/}:${LINENO}] '
    set -x
    log "debug on; PATH=${PATH} AWS_PROFILE=${AWS_PROFILE:-<unset>} ZONES_FILE=${ROUTE53_DDNS_ZONES_FILE:-<unset>}"
    if command -v aws >/dev/null 2>&1; then aws --version || true; fi
    if command -v curl >/dev/null 2>&1; then curl --version | head -n1 || true; fi
  fi
}

# Print failing command and line on error when debug is enabled
trap 'rc=$?; if [[ "${ROUTE53_DDNS_DEBUG:-}" =~ ^(1|true|yes|on)$ ]]; then err "ERR at ${BASH_SOURCE[0]##*/}:${LINENO}: ${BASH_COMMAND} (rc=${rc})"; fi; exit $rc' ERR

DRY_RUN=false
ZONES_FILE="${ROUTE53_DDNS_ZONES_FILE:-}"
WAN_IP_OVERRIDE="${ROUTE53_DDNS_WAN_IP:-}"
SKIP_LOOKUP=false
enable_debug
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=true; shift ;;
    -f|--zones-file) ZONES_FILE=${2:-}; shift 2 ;;
    -w|--wan-ip) WAN_IP_OVERRIDE=${2:-}; shift 2 ;;
    --skip-current-lookup) SKIP_LOOKUP=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { err "Missing required tool: $1"; exit 1; }; }
need curl
# Only require AWS CLI when we intend to write (non-dry-run). Reads have fallbacks.
if [[ "$DRY_RUN" != true ]]; then
  need aws
fi

# Discover WAN IPv4 (fallback chain)
discover_ip() {
  # IPv4-only regex (simple)
  local re='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
  local ip
  for url in \
    'https://api.ipify.org' \
    'https://checkip.amazonaws.com' \
    'https://ifconfig.me/ip'
  do
    ip=$(curl -4 -fsS --max-time 4 "$url" | tr -d '\n' | tr -d '\r' || true)
    if [[ -n "$ip" && "$ip" =~ $re ]]; then
      printf '%s' "$ip"
      return 0
    fi
  done
  return 1
}

WAN_IP="${WAN_IP_OVERRIDE:-}"
if [[ -z "$WAN_IP" ]]; then
  WAN_IP="$(discover_ip || true)"
fi
if [[ -z "$WAN_IP" ]]; then
  err "Failed to discover WAN IPv4 via ipify/checkip/ifconfig.me"
  exit 1
fi

# Map apex domains -> hosted zone IDs (edit as needed)
declare -A ZONES

load_zones_file() {
  local file=$1
  [[ -f "$file" ]] || { err "Zones file not found: $file"; exit 1; }
  local line key val count=0
  # shellcheck disable=SC2162
  while IFS= read -r line; do
    # strip leading/trailing whitespace
    line="${line%%[$'\r\n']*}"
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    # Try KEY=VAL
    if [[ "$line" =~ ^[[:space:]]*([^=,#[:space:]]+)[[:space:]]*=[[:space:]]*([^,#[:space:]]+) ]]; then
      key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
    # Try KEY,VAL
    elif [[ "$line" =~ ^[[:space:]]*([^,#[:space:]]+)[[:space:]]*,[[:space:]]*([^,#[:space:]]+) ]]; then
      key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
    # Try whitespace separated
    elif [[ "$line" =~ ^[[:space:]]*([^[:space:]]+)[[:space:]]+([^[:space:]]+) ]]; then
      key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
    else
      log "skip unrecognized zones line: $line"
      continue
    fi
    ZONES["$key"]="$val"
    count=$((count+1))
  done < "$file"
  if [[ $count -eq 0 ]]; then
    err "Zones file empty: $file"
    exit 1
  fi
  log "loaded $count zone mappings from $file"
}

# Determine zone mappings source
if [[ -n "$ZONES_FILE" ]]; then
  load_zones_file "$ZONES_FILE"
elif [[ -f /etc/route53-apex-ddns.zones ]]; then
  ZONES_FILE=/etc/route53-apex-ddns.zones
  load_zones_file "$ZONES_FILE"
else
  # Built-in defaults (edit if not using a zones file)
  ZONES=(
    [cyphai.com]=Z02889471UKP31JE18HPE
    [neuance.net]=Z0726808X55WJNUN7BTX
    [paulcapestany.com]=Z03183593TRC0TQ7HVQYU
  )
fi

TTL=60
changes_made=0
for domain in "${!ZONES[@]}"; do
  hz="${ZONES[$domain]}"
  current=""
  if [[ "$SKIP_LOOKUP" != true && ! "${ROUTE53_DDNS_SKIP_LOOKUP:-}" =~ ^(1|true|yes|on)$ ]]; then
    # Try to read current A from Route 53 (may fail if IAM lacks ListResourceRecordSets)
    current=$(aws route53 list-resource-record-sets --hosted-zone-id "$hz" \
          --query "ResourceRecordSets[?Type=='A' && Name=='${domain}.'].ResourceRecords[0].Value" \
          --output text 2>/dev/null || true)
    # Fallback to public DNS if read is unavailable/denied
    if [[ -z "$current" || "$current" == "None" ]]; then
      # DNS-over-HTTPS (Cloudflare)
      current=$(curl -fsS -H 'accept: application/dns-json' \
        "https://cloudflare-dns.com/dns-query?name=${domain}&type=A" \
        | grep -oE '"data":"([0-9]{1,3}\.){3}[0-9]{1,3}"' \
        | head -n1 | sed -E 's/.*"data":"([0-9\.]+)".*/\1/' || true)
      # Fallback to dig if available
      if [[ -z "$current" ]] && command -v dig >/dev/null 2>&1; then
        current=$(dig +time=3 +tries=1 +short @1.1.1.1 "$domain" A | head -n1 || true)
      fi
      # Fallback to system resolver
      if [[ -z "$current" ]]; then
        current=$(getent hosts "$domain" 2>/dev/null | awk '{print $1; exit}' || true)
      fi
    fi
  else
    log "skip current lookup for $domain (CI/offline)"
  fi
  if [[ "$current" == "$WAN_IP" ]]; then
    log "$domain already $WAN_IP"
    continue
  fi

  log "Plan: set $domain A -> $WAN_IP (was: ${current:-<none>})"
  if [[ "$DRY_RUN" == true ]]; then
    continue
  fi

  tmpfile=$(mktemp)
  cat > "$tmpfile" <<EOF
{"Comment":"DDNS update for ${domain}",
 "Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"${domain}","Type":"A","TTL":${TTL},"ResourceRecords":[{"Value":"${WAN_IP}"}]}}]}
EOF
  aws route53 change-resource-record-sets --hosted-zone-id "$hz" --change-batch "file://$tmpfile" >/dev/null
  rm -f "$tmpfile"
  log "Updated $domain A to $WAN_IP"
  changes_made=1
done

if [[ "$DRY_RUN" == true ]]; then
  log "Dry-run complete. No changes sent to Route 53."
fi

exit 0
