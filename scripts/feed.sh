#!/usr/bin/env bash
set -euo pipefail
TOPIC=${1:-adage.demo.mongodb.cdc.v1}
FILE=$2
if [[ ! -f "$FILE" ]]; then echo "Missing file $FILE"; exit 1; fi
CID=$(docker ps --format '{{.Names}}' | grep redpanda)
docker exec -i "$CID" rpk topic create "$TOPIC" >/dev/null 2>&1 || true
docker exec -i "$CID" rpk topic produce "$TOPIC" < "$FILE"
