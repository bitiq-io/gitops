#!/usr/bin/env bash
set -Eeuo pipefail

# WAN IP source (simple & reliable)
WAN_IP="$(curl -fsS https://checkip.amazonaws.com | tr -d '\n')"
if [[ -z "$WAN_IP" ]]; then
  echo "[route53-ddns] Failed to discover WAN IP" >&2
  exit 1
fi

# Map apex domains -> hosted zone IDs (edit as needed)
declare -A ZONES=(
  [cyphai.com]=Z02889471UKP31JE18HPE
  [neuance.net]=Z0726808X55WJNUN7BTX
  [paulcapestany.com]=Z03183593TRC0TQ7HVQYU
)

changed=0
for domain in "${!ZONES[@]}"; do
  hz="${ZONES[$domain]}"
  cur=$(aws route53 list-resource-record-sets --hosted-zone-id "$hz" \
        --query "ResourceRecordSets[?Type=='A' && Name=='${domain}.'].ResourceRecords[0].Value" \
        --output text 2>/dev/null || true)
  if [[ "$cur" != "$WAN_IP" ]]; then
    cat > /tmp/change-${domain}.json <<EOF
{"Comment":"DDNS update for ${domain}",
 "Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"${domain}","Type":"A","TTL":60,"ResourceRecords":[{"Value":"${WAN_IP}"}]}}]}
EOF
    aws route53 change-resource-record-sets --hosted-zone-id "$hz" --change-batch file:///tmp/change-${domain}.json >/dev/null
    echo "[route53-ddns] Updated ${domain} A to ${WAN_IP}"
    changed=1
  else
    echo "[route53-ddns] ${domain} already ${WAN_IP}"
  fi
done

exit 0

