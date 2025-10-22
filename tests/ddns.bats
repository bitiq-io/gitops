#!/usr/bin/env bats

setup() {
  REPO_ROOT=$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)
  SCRIPT="$REPO_ROOT/scripts/route53-apex-ddns.sh"
  ZONES="$REPO_ROOT/docs/examples/route53-apex-ddns.zones"
}

@test "ddns dry-run with skip lookup produces plans and exits 0" {
  [ -f "$SCRIPT" ]
  [ -f "$ZONES" ]
  ROUTE53_DDNS_WAN_IP=203.0.113.10 \
  ROUTE53_DDNS_ZONES_FILE="$ZONES" \
  ROUTE53_DDNS_SKIP_LOOKUP=1 \
  ROUTE53_DDNS_DEBUG=1 \
  run bash "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Plan: set cyphai.com A -> 203.0.113.10"* ]]
  [[ "$output" == *"Dry-run complete"* ]]
}

