## Naming & hygiene (quick rules)

- **Tables**

  - **Raw:** `raw_<source>`
  - **Parsed:** `parsed_<source>`
  - **Facts:** `fact_<thing>_<grain>` (e.g., fact_events_minute)

- **Views**

  - **Union:** `parsed_all`
  - **Semantics:** `vw_events, vw_alerts, vw_changes, vw_comments`
  - **Enriched:** suffix with `_enriched`

- **Performance**

  - **Keep JSON parsing in one MV** (raw→parsed).
  - Facts do **GROUP BY** only; no JSON work.
  - Views are **SELECT/WHERE/LEFT JOIN** only; no heavy compute.

- **Rule of thumb**

  - Facts are additive (counts/sums) or snapshot-safe (ReplacingMergeTree).
  - Keep keys small; TTL long.

### That’s it:

- **Facts** give you instant panels;
- **Views** give you a stable contract for Grafana and ML
- no tool knows (or cares) which source produced the data

## Examples

### MongoDB CDC

- Fact: `fact_orders_per_minute` (count creates/updates/deletes per ns)
- Fact: `fact_order_failures` (subset where status in ('failed','payment_failed'))

### Jira

- Fact: `fact_ticket_changes` (count tickets moving into “In Progress”)
- Fact: `fact_ticket_resolution_time` (median minutes from Open → Done)

### Splunk / Dynatrace

- Fact: `fact_alerts_per_service` (counts by severity, ns, service_name)
- Fact: `fact_mttd` (time between log error and first alert raised)

### Commits (Git)

- Fact: `fact_commits_per_ticket` (link commit SHA → Jira ID)
- Fact: `fact_lead_time` (commit → deploy)

## QA gates you can automate (per fact)

- **Shape check:** `SELECT count() FROM <fact> WHERE toDate(bucket)=today() > 0`
- **Dim hygiene:** no empty strings in required dims.
- **Cardinality guard:** `uniqExact(ns)` under threshold.
- **Latency sanity (if relevant):** p95_ms < sane cap.
- **Drift watch:** compare last 7d vs prior 7d totals.
