# Fabric

**Fabric** is a universal, governance-first pattern for unifying event streams.  
It runs on **Kafka (Redpanda) + ClickHouse + Grafana** and provides a consistent path:

```
raw → parsed → facts → views
```

## Why Fabric?

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
   - Used by Grafana and ML, not tied to any one tool.

## Quickstart

```bash
git clone https://github.com/usekarma/adage-fabric.git
cd adage-fabric

# 1. Bring up Redpanda, ClickHouse, Grafana
make up

# 2. Bootstrap shared tables, lanes, and views (schema only)
make sql.bootstrap
```

This starts:

- Redpanda (Kafka API) on :9092  
- ClickHouse on :8123 (HTTP) and :9000 (native)  
- Grafana on :3000 (admin/admin, with starter dashboards)

Feed sample fixtures into Kafka and query in ClickHouse or view dashboards at [http://localhost:3000](http://localhost:3000).

### Useful commands

```bash
make down        # stop containers
make restart     # restart stack
make ps          # show container status
make logs        # stream container logs

cd sql
make lane SOURCE=mongodb STREAM=cdc ORG=adage DOMAIN=demo VERSION=1  # render+apply one lane
make lanes       # apply all lanes/*.sql already rendered
```

## Querying ClickHouse

You can interact with ClickHouse directly in several ways:

**Interactive client inside the container:**
```bash
docker exec -it $(docker ps --format '{{.Names}}' | grep clickhouse | head -n1) clickhouse-client
```
Then run SQL:
```sql
SHOW DATABASES;
USE default;
SHOW TABLES;
SELECT * FROM parsed_mongodb_cdc LIMIT 10;
```

**One-liner from host:**
```bash
docker exec -i $(docker ps --format '{{.Names}}' | grep clickhouse | head -n1)   clickhouse-client -q "SHOW TABLES FROM default"
```

**Web UI:**  
Open [http://localhost:8123/play](http://localhost:8123/play) in a browser for a simple SQL console.

**Grafana:**  
Grafana (http://localhost:3000) is pre-configured to use ClickHouse as a datasource. Dashboards query tables like `fact_events_minute_all` and `fact_latency_minute_all`.

## Testing

Run all test cases:

```bash
while read -r c; do ./scripts/run_case.sh "$c"; done < tests/test_matrix.txt
```

Run one test case:

```bash
./scripts/run_case.sh case_orders_happy || true
```

Generate snapshots from current DB state:

```bash
./scripts/query.sh "
  SELECT ts_event, source, event_type, ns, event_id, severity, op, status
  FROM parsed_mongodb
  ORDER BY ts_event, event_id
  FORMAT CSV" > expected/case_orders_happy.parsed.csv
```

Repeat for facts, etc. Future runs will diff against these CSVs.

## Repo Structure

```
adage-fabric/
  Makefile                 # root: orchestrates docker compose + sql bootstrap
  docker-compose.yml       # Redpanda + ClickHouse + Grafana
  provisioning/            # environment provisioning assets (e.g., dashboards, configs)
  sql/                     # schema Makefile + DDL templates
    Makefile               # schema only (no docker compose)
    templates/             # lane template (envsubst)
    lanes/                 # rendered lane SQL
    shared/                # global rollups and views
  fixtures/                # JSONL input files (test cases)
  expected/                # expected CSV snapshots
  scripts/                 # feed, query, reset
  dashboards/              # Grafana dashboards
  docs/                    # design notes
```

## Documentation

- [docs/fact_template.md](docs/fact_template.md) — checklist for designing facts.  
- [docs/join_strategy.md](docs/join_strategy.md) — where to join (CH, Grafana, ML).  

## Roadmap

- [ ] Add sample source mappings (Mongo CDC, Jira, Splunk).  
- [ ] Provide canonical dims (`service`, `ticket_id`, `env`).  
- [ ] Ship async enrichment slot (entropy, anomalies, embeddings).  
- [ ] Expand starter Grafana dashboards.  
- [ ] Tag `v0.1` once schema and dashboards are stable for demo.

## Optional niceties

- Parametrize the topic per case (adage.demo.${CASE}.v1) to avoid consumer-offset interference (or run ALTER TABLE kafka_mongodb_cdc MODIFY SETTING kafka_group_name='fabric_demo_$$RANDOM' before each case).
- If you later add async enrichment, add expected CSVs for the enriched view too.

## Suggestions to polish / demo improvements

| Area | Suggestion |
|---|---|
| **Bootstrap SQL** | Ensure `sql/Makefile bootstrap` (or equivalent) defines all raw/parsed/facts/views tables, so a fresh clone + `make bootstrap` yields queryable data. |
| **Examples** | Add more fixture cases: e.g., delete events, late arrivals, out-of-order timestamps — to stress parsing logic in obvious ways. |
| **Dashboard defaults** | Ship Grafana dashboards that display something out-of-the-box (e.g., events per minute from facts). Provide a sample fixture so panels aren’t blank on first run. |
| **Scripts** | Continue to tighten helper scripts (`run_case.sh`, `query.sh`) for repeatable demos. |
| **Version tagging / releases** | Tag `v0.1` when reaching a minimum usable demo state. |
| **Readme front matter** | Add a screenshot (Grafana panel) once populated. Consider an FAQ clarifying *what Fabric is* vs *what it isn’t* (demo vs production). |

## License

Apache 2.0 — free to use, adapt, and extend.  
Authored by [usekarma](https://github.com/usekarma).
