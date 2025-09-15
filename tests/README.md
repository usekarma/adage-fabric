# Tests and Fixtures

This folder defines JSONL fixtures and a simple test runner that:
1) Produces the fixture into Redpanda (Kafka).
2) Waits briefly for materialized views to populate.
3) Exports "actual" CSVs from ClickHouse.
4) (Optional) diffs against expected CSV snapshots in `expected/`.

## Layout
- `fixtures/*.jsonl` — input events (one JSON per line).
- `tests/test_matrix.txt` — list of fixture basenames to run.
- `scripts/run_case.sh` — runner for a single case.

## Usage

Run all cases:
```bash
while read -r c; do ./scripts/run_case.sh "$c"; done < tests/test_matrix.txt
```

Run a single case:
```bash
./scripts/run_case.sh case_orders_happy
```

## Updating expected snapshots

After validating outputs, you can snapshot current results:
```bash
./scripts/query.sh "
  SELECT ts_event, source, event_type, ns, event_id, severity, op, status
  FROM parsed_all
  WHERE ts_event >= now() - INTERVAL 1 DAY
  ORDER BY ts_event, event_id
  FORMAT CSV" > expected/<case>.parsed.csv

./scripts/query.sh "
  SELECT t_min, ns, event_type, op, c
  FROM fact_events_minute_all
  WHERE t_min >= now() - INTERVAL 1 DAY
  ORDER BY t_min, ns, event_type, op
  FORMAT CSV" > expected/<case>.facts.csv
```
