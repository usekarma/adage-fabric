#!/usr/bin/env bash
set -euo pipefail

CASE=$1
TOPIC=${TOPIC:-adage.demo.mongodb.cdc.v1}
ROOT=$(cd "$(dirname "$0")/.."; pwd)

# Reset tables
"$ROOT/scripts/query.sh" "SOURCE '$ROOT/sql/90_reset.sql'"

# Feed fixtures
"$ROOT/scripts/feed.sh" "$TOPIC" "$ROOT/fixtures/${CASE}.jsonl"

# Small wait to allow MV consumption
sleep 2

# Query actuals (stable ordering)
ACT_PARSED=$(mktemp)
ACT_FACTS=$(mktemp)
"$ROOT/scripts/query.sh" "
  SELECT ts_event, source, event_type, ns, event_id, severity, op, status
  FROM parsed_mongodb
  ORDER BY ts_event, event_id
  FORMAT CSV" > "$ACT_PARSED"
"$ROOT/scripts/query.sh" "
  SELECT t_min, ns, event_type, c
  FROM facts_events_minute
  ORDER BY t_min, ns, event_type
  FORMAT CSV" > "$ACT_FACTS"

# Compare to expected snapshots
diff -u "$ROOT/expected/${CASE}.parsed.csv" "$ACT_PARSED"
diff -u "$ROOT/expected/${CASE}.facts.csv" "$ACT_FACTS"
echo "✅ ${CASE} passed."
