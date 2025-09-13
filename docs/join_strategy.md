# Join Strategy in Fabric

Fabric handles multiple event sources (Mongo CDC, Jira, Splunk, Git, ServiceNow, Dynatrace, etc.).  
Not every stream should be joined the same way. This guide defines **where** to join (ClickHouse vs Grafana vs ML) and **why**.

---

## Rules of Thumb

1. **Join in ClickHouse (CH)** when you have a **clean, low-cardinality key** (e.g., ticket_id, commit_sha, service).  
2. **Overlay in Grafana** when you just want **temporal correlation** without schema work.  
3. **Join in ML** when relationships are **temporal or fuzzy**, or you want to learn **lag/lead**.  

---

## Join Strategy Matrix

| Source A ↔ Source B     | Natural keys?         | Recommended join | Why | Example |
|--------------------------|----------------------|-----------------|-----|---------|
| **Git** ↔ **Jira**       | ticket_id in commit  | CH              | Clear stable key, high ROI | commits per ticket |
| **Jira** ↔ **ServiceNow**| Sometimes weak refs  | ML              | Heterogeneous IDs, learn lag/lead | incidents following tickets |
| **Mongo CDC** ↔ **ServiceNow** | No direct key | Grafana → ML    | Visual overlay first, then ML window join | db events → tickets |
| **Splunk** ↔ **Dynatrace**| service, host, pod  | CH (if dims canonicalized) | Dim mapping unlocks join | alerts per service |
| **CI/CD** ↔ **Incidents**| service + time       | ML              | Temporal by nature | deploys before incidents |
| **Teams/Email** ↔ **Jira**| ticket refs in text | CH (if present) else ML | Regex extract → join, else embedding | comments per ticket |
| **CloudTrail** ↔ **Incidents** | account_id, service | CH + ML       | Coarse joins for dashboards, ML for causality | API calls before outage |

---

## Canonical Dimensions

Standardize these early to unlock safe joins:
- `service` (from k8s labels, repo names, hostnames)
- `env` (`prod`, `stage`, `dev`)
- `ticket_id` (regex from commits/messages)
- `account_id`, `region` (for cloud events)
- `ns` (Mongo namespace/logical table)

Maintain a `dim_service` mapping table.

---

## ClickHouse Join Patterns

**Keyed join (safe):**
```sql
SELECT g.commit_ts, j.ts_event AS ticket_ts, j.ticket_id, g.commit_sha, g.author
FROM parsed_git g
INNER JOIN parsed_jira j USING (ticket_id)
WHERE g.commit_ts >= now()-INTERVAL 7 DAY;
```

**Time-window join (use for dashboards, not warehouses):**
```sql
WITH d AS (
  SELECT t_min, service, sum(c) AS deploys
  FROM fact_deploys_minute GROUP BY t_min, service
),
i AS (
  SELECT t_min, service, sum(c) AS incidents
  FROM fact_incidents_minute GROUP BY t_min, service
)
SELECT
  d.t_min, d.service, deploys,
  sumIf(i.incidents, i.t_min BETWEEN d.t_min AND d.t_min + INTERVAL 30 MINUTE) AS incidents_next_30m
FROM d
LEFT JOIN i ON i.service = d.service
ORDER BY d.t_min;
```

---

## Grafana Overlay (no join)

- Two queries, same time range (e.g., Splunk errors vs ServiceNow incidents).  
- Overlay in one panel or side-by-side panels.  
- Fastest way to validate correlation before schema work.

---

## ML Feature Joins

- Align streams on time buckets.  
- Build lag/lead features (e.g., errors_t-5m, deploys_t-15m, tickets_t+30m).  
- Let the model learn causality and weights, don’t force upstream schema joins.

---

## 🚫 Red Flags

- Don’t join on free-text fields (e.g., usernames) without canonical dims.  
- Don’t join on high-cardinality IDs (request IDs, UUIDs across silos).  
- Don’t parse JSON in facts — always parse once in `mv_raw_to_parsed`.  

---

## What to Encode in Fabric v0.1

- **CH joins you will ship:**  
  - Git ↔ Jira (via ticket_id)  
  - Alerts ↔ dim_service (via service)  
- **Grafana side-by-side only:**  
  - Splunk vs Incidents  
  - Mongo CDC vs Tickets  
  - Deploys vs Incidents  
- **ML joins:**  
  - Temporal couplings with lag/lead features (errors → tickets, deploys → incidents)

---

Fabric stays lean if you **join only where safe**, visualize correlations early, and push messy causality to ML.
