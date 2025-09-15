#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/run_case.sh case_orders_happy [TOPIC]
TOPIC_DEFAULT="adage.demo.mongodb.cdc.v1"
SLEEP_AFTER_FEED=8

CASE="${1:-}"
if [[ -z "${CASE}" ]]; then
  echo "Usage: $0 <fixture_basename> [topic]" >&2
  exit 1
fi
TOPIC="${2:-$TOPIC_DEFAULT}"
FIX="fixtures/${CASE}.jsonl"
[[ -f "${FIX}" ]] || { echo "Fixture not found: ${FIX}" >&2; exit 1; }

# Helper to run CH SQL
ch() { ./scripts/query.sh --query "$1"; }

echo "→ Producing ${FIX} to ${TOPIC}"
make -s feed FILE="${FIX}" TOPIC="${TOPIC}" || { echo "Make feed failed"; exit 1; }

# Nudge Kafka engine to consume (helpful on some CH versions)
echo "→ Waiting ${SLEEP_AFTER_FEED}s for materialized views"
sleep "${SLEEP_AFTER_FEED}"

echo "→ Parsed rows in last 10m:"
ch "SELECT count() FROM parsed_mongodb_cdc WHERE ts_ingest >= now() - INTERVAL 10 MINUTE"

echo "→ Facts rows in last 10m:"
ch "SELECT sum(c) FROM fact_events_minute_all WHERE t_min >= now() - INTERVAL 10 MINUTE"

# Optional: dump a peek at recent parsed rows for sanity
mkdir -p tmp
./scripts/query.sh --query "
  SELECT ts_event, event_type, ns, event_id, severity, op
  FROM parsed_mongodb_cdc
  WHERE ts_ingest >= now() - INTERVAL 10 MINUTE
  ORDER BY ts_ingest DESC
  LIMIT 10
  FORMAT CSV" > "tmp/${CASE}.peek.csv"

echo "✓ Case ${CASE} complete"
