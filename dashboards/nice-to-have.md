
### op mix by namespace

```
SELECT ns, op, count() AS c
FROM parsed_mongodb
WHERE ts_ingest BETWEEN $__fromTime AND $__toTime
GROUP BY ns, op
ORDER BY c DESC
```

### lag panel (if you add a ts_produced field in fixtures):

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