#!/usr/bin/env bash
# Portable ClickHouse query helper for docker-compose setups.
# Usage:
#   ./scripts/query.sh --query "SELECT 1"
#   ./scripts/query.sh < some.sql      # multi-statement via stdin
#   echo "SELECT 1" | ./scripts/query.sh
#
# Assumes your ClickHouse service in docker-compose.yml is named 'clickhouse'.
# Change CH_SERVICE below if different.

set -euo pipefail

CH_SERVICE="${CH_SERVICE:-clickhouse}"

if [[ "${1:-}" == "--query" ]]; then
  shift
  Q="${1:-}"
  if [[ -z "${Q}" ]]; then
    echo "Error: empty --query string" >&2
    exit 1
  fi
  exec docker compose exec -T "${CH_SERVICE}" clickhouse-client -q "${Q}"
else
  # If stdin is a TTY, warn; otherwise pass through to -n (multi-statement)
  if [ -t 0 ]; then
    echo "Reading from stdin; press Ctrl-D to end." >&2
  fi
  exec docker compose exec -T "${CH_SERVICE}" clickhouse-client -n
fi
