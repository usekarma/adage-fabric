# Fabric

**Fabric** is a universal, governance‑first pattern for unifying event streams.  
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
- **ML‑ready:** Expose stable views for downstream enrichment and modeling.

## Quickstart

```bash
git clone https://github.com/usekarma/adage-fabric.git
cd adage-fabric

# 1) Start core services (Redpanda, ClickHouse, Grafana)
make up

# 2) Bootstrap shared tables, lanes, and views (schema only)
make sql.bootstrap
```

This starts:

- Redpanda (Kafka API) on :9092  
- ClickHouse on :8123 (HTTP) and :9000 (native)  
- Grafana on :3000 (admin/admin, with starter dashboards)

Feed sample fixtures into Kafka and query in ClickHouse or view dashboards at <http://localhost:3000>.

### Optional add‑ons (profiles)

Services are opt‑in via **Compose profiles** so they never auto‑start during `make up` / `make bootstrap`:

- **Kafka UI** (profile: `ui`): `make kafka-ui` or `docker compose --profile ui up -d kafka-ui` → <http://localhost:8080>
- **Flink** (profile: `flink`): `docker compose --profile flink up -d`
- **Kafka Connect (Debezium)** (profile: `connect`): `docker compose --profile connect up -d`
- **MongoDB (replica set for CDC)** (profile: `mongo`): `docker compose --profile mongo up -d`

If you want *everything* (core + UI) at once:
```bash
make up.all
```

### Useful commands

```bash
make help        # show commands and descriptions
make down        # stop containers
make restart     # restart core stack
make logs        # stream container logs
make clean       # stop + remove volumes (fresh state)

# Kafka helpers
make feed FILE=fixtures/case_orders_happy.jsonl TOPIC=adage.demo.mongodb.cdc.v1
make topic.ensure TOPIC=adage.demo.mongodb.cdc.v1
make topic.create TOPIC=adage.demo.mongodb.cdc.v1

# Lanes (DDL)
cd sql
make lane SOURCE=mongodb STREAM=cdc ORG=adage DOMAIN=demo VERSION=1
make lanes       # apply all rendered lanes/*.sql
```

## How it works (Architecture)

1) **Raw**
   - Ingest directly from Kafka (Redpanda) using a ClickHouse **Kafka Engine** table.
   - Short TTL (e.g., 3 days). Append‑only; no expensive transforms here.
   - Responsibility: get bytes in reliably.

2) **Parsed**
   - Materialized View (MV) from `raw` extracts JSON once and writes to a typed **MergeTree** table.
   - Longer TTL (e.g., 90 days). Stable column types; add light denorm if helpful.
   - Responsibility: make events queryable and inexpensive to scan.

3) **Facts**
   - Domain rollups (counts, rates, latencies) with clear grains (minute/hour/day).
   - Prefer additive engines (e.g., `SummingMergeTree`) or snapshots with explicit grain keys.
   - Responsibility: cheap dashboards and SLO views.

4) **Views**
   - Semantic SELECTs (e.g., `vw_events`, `vw_alerts`, `vw_changes`) joining multiple sources.
   - This layer is what Grafana and downstream ML read from; treat as your contract.
   - Responsibility: stable API for external consumption.

> TL;DR: Kafka Engine ➜ MV ➜ MergeTree ➜ Facts ➜ Views

## Querying ClickHouse

**Interactive client inside the container:**
```bash
docker compose exec -it clickhouse clickhouse-client
```
Then run SQL:
```sql
SHOW DATABASES;
USE default;
SHOW TABLES;
SELECT * FROM parsed_mongodb_cdc LIMIT 10;
```

**One‑liner from host:**
```bash
docker compose exec -i clickhouse clickhouse-client -q "SHOW TABLES FROM default"
```

**Web UI:**  
Open <http://localhost:8123/play> for a simple SQL console.

**Grafana:**  
Grafana (<http://localhost:3000>) is pre‑configured to use ClickHouse as a datasource. Dashboards query tables like `fact_events_minute_all` and `fact_latency_minute_all`.

## Testing

You can run the entire matrix or a single case.

**Run the whole matrix** (defaults to `tests/test_matrix.txt`):  
```bash
make test.all
```
Override the matrix file:  
```bash
make test.all MATRIX=tests/smoke.txt
```

**Run one named case** (convenience target):  
```bash
make test.orders
```

**Or call the runner directly:**  
```bash
./scripts/run_case.sh case_orders_happy
```

> The matrix format is one case name per line; blank lines and `#` comments are ignored. Example:
> ```
> # tests/test_matrix.txt
> case_orders_happy
> # case_orders_delete   (uncomment when fixture is ready)
> ```

**Generate expected snapshots** from current DB state (example for parsed):  
```bash
./scripts/query.sh "
  SELECT ts_event, source, event_type, ns, event_id, severity, op, status
  FROM parsed_mongodb_cdc
  ORDER BY ts_event, event_id
  FORMAT CSV" > expected/case_orders_happy.parsed.csv
```
Repeat for facts, etc. Future runs will diff against these CSVs.


**Generate expected snapshots** with Make targets:

```bash
# parsed snapshot
make snap.parsed CASE=case_orders_happy

# facts snapshot (defaults to fact_events_minute_all)
make snap.facts CASE=case_orders_happy

# override fact table/columns
make snap.facts CASE=case_orders_happy FACT_TABLE=fact_latency_minute_all FACT_COLUMNS='t_min, p50_ms, p95_ms, p99_ms'

# custom query snapshot (you supply SQL that ends with FORMAT CSV)
make snap.custom CASE=case_orders_happy NAME=my_view \\
  SQL='SELECT * FROM vw_events ORDER BY ts_event FORMAT CSV'

# do parsed + default facts in one shot
make snap.all CASE=case_orders_happy
```


## Repo Structure

```
adage-fabric/
  Makefile                 # root: compose orchestration + sql bootstrap
  docker-compose.yml       # core services + optional services behind profiles
  provisioning/            # environment provisioning assets (e.g., dashboards, configs)
  dashboards/              # Grafana dashboards
  sql/                     # schema Makefile + DDL templates
    Makefile               # schema only (no docker compose)
    templates/             # lane template (envsubst)
    lanes/                 # rendered lane SQL
    shared/                # global rollups and views
  connectors/              # (optional) Kafka Connect configs (e.g., mongodb-cdc.json)
  fixtures/                # JSONL input files (test cases)
  expected/                # expected CSV snapshots
  scripts/                 # feed, query, reset
  tests/                   # test matrix and helpers
  docs/                    # design notes
```

## Documentation

- `docs/fact_template.md` — checklist for designing facts.  
- `docs/join_strategy.md` — where to join (CH, Grafana, ML).  

## Roadmap

- [ ] Add sample source mappings (Mongo CDC, Jira, Splunk).  
- [ ] Provide canonical dims (`service`, `ticket_id`, `env`).  
- [ ] Ship async enrichment slot (entropy, anomalies, embeddings).  
- [ ] Expand starter Grafana dashboards.  
- [ ] Tag `v0.1` once schema and dashboards are stable for demo.

## Optional niceties

- Parametrize the topic per case (`adage.demo.${CASE}.v1`) to avoid consumer‑offset interference (or run `ALTER TABLE kafka_mongodb_cdc MODIFY SETTING kafka_group_name='fabric_demo_$$RANDOM'` before each case).
- If you later add async enrichment, add expected CSVs for the enriched view too.

## Suggestions to polish / demo improvements

| Area | Suggestion |
|---|---|
| **Examples** | Add more fixture cases: e.g., delete events, late arrivals, out-of-order timestamps — to stress parsing logic in obvious ways. |
| **Dashboard defaults** | Ship Grafana dashboards that display something out-of-the-box (e.g., events per minute from facts). Provide a sample fixture so panels aren’t blank on first run. |
| **Version tagging / releases** | Tag `v0.1` when reaching a minimum usable demo state. |
| **Readme front matter** | Add a screenshot (Grafana panel) once populated. Consider an FAQ clarifying *what Fabric is* vs *what it isn’t* (demo vs production). |

## License

Apache 2.0 — free to use, adapt, and extend.  
Authored by [usekarma](https://github.com/usekarma).
