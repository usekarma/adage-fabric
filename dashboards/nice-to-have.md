
### op mix by namespace

```
SELECT ns, op, count() AS c
FROM parsed_mongodb
WHERE ts_ingest BETWEEN $__fromTime AND $__toTime
GROUP BY ns, op
ORDER BY c DESC
```

### Lag panel (if you add a ts_produced field in fixtures):

```
SELECT
  toStartOfMinute(ts_ingest) AS time,
  avg(dateDiff('millisecond', ts_event, ts_ingest)) AS avg_ms
FROM parsed_mongodb
WHERE ts_ingest BETWEEN $__fromTime AND $__toTime
GROUP BY time
ORDER BY time
```

### Dashboard variable for ns

Variable query: `SELECT DISTINCT ns FROM parsed_mongodb ORDER BY ns`

Then add `WHERE ns IN (${ns:sqlstring})` to panel queries.

### Events per minute by namespace

```
SELECT t_min AS time, ns, sum(c) AS value
FROM fact_events_minute
WHERE t_min BETWEEN $__fromTime AND $__toTime
GROUP BY t_min, ns
ORDER BY t_min
```

### Recent alerts table

```
SELECT ts_ingest, source, ns, severity, status, message
FROM vw_alerts
WHERE ts_ingest BETWEEN $__fromTime AND $__toTime
ORDER BY ts_ingest DESC
LIMIT 500
```

### Latency trend

```
SELECT t_min AS time, ns, p95_ms AS value
FROM fact_latency_minute
WHERE t_min BETWEEN $__fromTime AND $__toTime
ORDER BY t_min
```

### Top noisy namespaces (last 24h)

```
SELECT ns, sum(c) AS events_24h
FROM fact_events_minute
WHERE t_min >= now() - INTERVAL 24 HOUR
GROUP BY ns
ORDER BY events_24h DESC
LIMIT 10
```

### Enriched anomalies (if using surprisal)

```
SELECT ts_ingest AS time, ns, surprisal_24h AS value
FROM vw_events_enriched
WHERE ts_ingest BETWEEN $__fromTime AND $__toTime
ORDER BY time
```
