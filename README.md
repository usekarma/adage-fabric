# Fabric

**Fabric** is a universal, governance-first pattern for unifying event streams.  
It runs on **Kafka + ClickHouse + Grafana** and provides a consistent path:

```
raw → parsed → facts → views
```

## ✨ Why Fabric?
Modern systems emit countless signals — CDC events, alerts, tickets, commits, logs. Each siloed stream makes sense in isolation, but operators need a single fabric to see the whole picture.  

Fabric gives you:
- **Simplicity:** Only Kafka, ClickHouse, and Grafana required.
- **Governance:** TTLs, cost bounds, and role separation baked in.
- **Extensibility:** Add new sources by defining raw → parsed mappings.
- **Observability:** Grafana dashboards on top of facts and views.
- **ML-ready:** Expose stable views for downstream enrichment and modeling.

## Pattern

1. **Raw**  
   - Direct ingest from Kafka.  
   - Append-only, short TTL (e.g., 3 days).  

2. **Parsed**  
   - Typed schema, JSON extracted once.  
   - Longer TTL (e.g., 90 days).  

3. **Facts**  
   - Domain-specific rollups (counts, rates, latencies).  
   - Additive or snapshot tables with clear grains (minute/hour).  

4. **Views**  
   - Semantic selects (e.g., `vw_events`, `vw_alerts`, `vw_changes`).  
   - Join or union multiple sources, normalize dimensions.  
   - Used by Grafana & ML, not tied to any one tool.

## Quickstart (Demo on a laptop)

```bash
git clone https://github.com/usekarma/adage-fabric.git
cd adage-fabric
docker compose up -d
```

This starts:
- **Redpanda (Kafka API)** on :9092  
- **ClickHouse** on :8123  
- **Grafana** on :3000 (admin/admin, with starter dashboards)

Feed sample fixtures into Kafka and query in ClickHouse or view dashboards at http://localhost:3000.

## Testing

### Run all test cases

```
while read -r c; do ./scripts/run_case.sh "$c"; done < tests/test_matrix.txt
```

### Run one test case

```
./scripts/run_case.sh case_orders_happy || true  # will diff-fail if expected missing
```

### Generate test case snapshots from current DB state:

Repeat for each fixture:

```
./scripts/query.sh "
  SELECT ts_event, source, event_type, ns, event_id, severity, op, status
  FROM parsed_mongodb
  ORDER BY ts_event, event_id
  FORMAT CSV" > expected/case_orders_happy.parsed.csv

./scripts/query.sh "
  SELECT t_min, ns, event_type, c
  FROM facts_events_minute
  ORDER BY t_min, ns, event_type
  FORMAT CSV" > expected/case_orders_happy.facts.csv
```

Now future runs compare actuals against these snapshots—true unit-test behavior for your pipeline.

### Tips for good CDC test cases

- **Happy path:** create → update → update (monotonic status).
- **Retry path:** create → update(warn) → update(info).
- **Delete path:** create → delete (op='d').
- **Out-of-order timestamps:** events with ts_event slightly out of order to ensure ordering doesn’t break logic.
- **Late arrival:** older ts_event produced last (check it still lands in correct partitions/order).
- **Noise fields:** extra keys in payload to verify your parser ignores unknowns.

## Repo Structure

```
adage-fabric/
  docker-compose.yml         # Redpanda + ClickHouse + Grafana
  sql/                       # Table DDLs (raw, parsed, facts, views)
  fixtures/                  # Sample JSONL input files (unit test cases)
  expected/                  # Expected outputs (parsed/facts snapshots)
  scripts/                   # Helpers to feed, reset, query
  dashboards/                # Grafana dashboards (JSON)
  docs/                      # Design notes, join strategy, fact templates
```

## Documentation

- [docs/fact_template.md](docs/fact_template.md) — checklist for designing facts.  
- [docs/join_strategy.md](docs/join_strategy.md) — where to join (CH, Grafana, ML).  

## Roadmap

- [ ] Add sample source mappings (Mongo CDC, Jira, Splunk).  
- [ ] Provide canonical dims (`service`, `ticket_id`, `env`).  
- [ ] Ship async enrichment slot (entropy, anomalies, embeddings).  
- [ ] Expand starter Grafana dashboards.  

### Optional niceties

- Add a Makefile with make up, make init, make test.
- Parametrize the topic per case (adage.demo.${CASE}.v1) to avoid consumer-offset interference (or run ALTER TABLE kafka_mongodb_cdc MODIFY SETTING kafka_group_name='fabric_demo_$$RANDOM' before each case).
- If you later add async enrichment, add expected CSVs for the enriched view too.

## 🚧 Suggestions to Polish / Demo Improvements

Here are a few things that would make Fabric easier for others to demo and adopt quickly:

| Area | Suggestion |
|---|---|
| **Bootstrap SQL** | Ensure `sql/00_init.sql` (or equivalent) defines all raw/parsed/facts/views tables, so a fresh clone + `docker compose up` immediately yields queryable data. Include Kafka engine source table if applicable. |
| **Examples** | Add more fixture cases: e.g., delete events, late arrivals, out‑of‑order timestamps — to stress parsing logic in obvious ways. |
| **Dashboard Defaults** | Ship Grafana dashboards that display something out‑of‑the‑box (e.g., events per minute from facts). Provide a sample fixture so panels aren’t blank on first run. |
| **Makefile / Scripts** | Add helper commands like `make up`, `make init`, `make test` to tie Docker + SQL + tests together. |
| **Version Tagging / Releases** | Tag `v0.1` when reaching a minimum usable demo state. Makes it clear this is the “first shareable version.” |
| **Readme Front Matter** | Add a screenshot (Grafana panel) once populated. Consider an FAQ section clarifying *what Fabric is* vs *what it isn’t* (research vs demo). |

## License

Apache 2.0 — free to use, adapt, and extend.  
Authored by [usekarma](https://github.com/usekarma).
