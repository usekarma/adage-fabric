#!/usr/bin/env bash
# Render a per-lane SQL from template using envsubst.
# Usage:
#   export ORG="adage" DOMAIN="demo" SOURCE="mongodb" STREAM="cdc" VERSION="1"
#   ./scripts/render_lane.sh > sql/lanes/mongodb_cdc.sql

set -euo pipefail
for v in ORG DOMAIN SOURCE STREAM VERSION; do
  if [[ -z "${!v:-}" ]]; then echo "Missing env var: $v" >&2; exit 1; fi
done

envsubst < "$(dirname "$0")/../sql/templates/fabric_lane_template.sql"
