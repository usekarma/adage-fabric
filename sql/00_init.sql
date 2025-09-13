CREATE TABLE IF NOT EXISTS kafka_mongodb_cdc
ENGINE = Kafka
SETTINGS
  kafka_broker_list = 'redpanda:9092',
  kafka_topic_list  = 'adage.demo.mongodb.cdc.v1',
  kafka_group_name  = 'fabric_demo_group',
  kafka_format      = 'JSONEachRow',
  kafka_num_consumers = 1;

CREATE TABLE IF NOT EXISTS raw_mongodb (
  ingest_ts    DateTime DEFAULT now(),
  topic        LowCardinality(String),
  partition_id Int32,
  offset       UInt64,
  key          String,
  value_json   String
)
ENGINE = MergeTree
PARTITION BY toDate(ingest_ts)
ORDER BY (topic, partition_id, offset)
TTL toDate(ingest_ts) + INTERVAL 3 DAY;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_kafka_to_raw
TO raw_mongodb AS
SELECT _topic AS topic, _partition AS partition_id, _offset AS offset,
       ifNull(_key,'') AS key, _raw AS value_json
FROM kafka_mongodb_cdc;

CREATE TABLE IF NOT EXISTS parsed_mongodb (
  ts_event     DateTime64(3),
  ts_ingest    DateTime64(3),
  source       LowCardinality(String),
  event_type   LowCardinality(String),
  ns           LowCardinality(String),
  event_id     String,
  severity     LowCardinality(String),
  op           LowCardinality(String),
  status       LowCardinality(String),
  message      String,
  payload_json String
)
ENGINE = MergeTree
PARTITION BY toDate(ts_event)
ORDER BY (ns, event_type, ts_event, event_id)
TTL toDate(ts_event) + INTERVAL 90 DAY;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_raw_to_parsed
TO parsed_mongodb AS
SELECT
  parseDateTime64BestEffort(JSONExtractString(value_json,'ts_event')) AS ts_event,
  now64(3) AS ts_ingest,
  JSONExtractString(value_json,'source')       AS source,
  JSONExtractString(value_json,'event_type')   AS event_type,
  JSONExtractString(value_json,'ns')           AS ns,
  JSONExtractString(value_json,'event_id')     AS event_id,
  lower(coalesce(JSONExtractString(value_json,'severity'), '')) AS severity,
  coalesce(JSONExtractString(value_json,'op'), '') AS op,
  coalesce(JSONExtractString(value_json,'payload.status'), '') AS status,
  left(coalesce(JSONExtractString(value_json,'payload.message'), ''), 2000) AS message,
  JSONExtractRaw(value_json,'payload') AS payload_json
FROM raw_mongodb;

CREATE TABLE IF NOT EXISTS facts_events_minute (
  t_min DateTime,
  ns    LowCardinality(String),
  event_type LowCardinality(String),
  op    LowCardinality(String),
  c     UInt64
)
ENGINE = SummingMergeTree
PARTITION BY toDate(t_min)
ORDER BY (t_min, ns, event_type, op)
TTL toDate(t_min) + INTERVAL 180 DAY;

CREATE MATERIALIZED VIEW mv_parsed_to_fact_minute
TO fact_events_minute AS
SELECT
  toStartOfMinute(ts_ingest) AS t_min,
  ns, event_type, op,
  count() AS c
FROM parsed_mongodb      -- repeat per source or UNION ALL a parsed_all view (see below)
GROUP BY t_min, ns, event_type, op;

CREATE TABLE fact_events_hour (
  t_hour DateTime,
  ns     LowCardinality(String),
  event_type LowCardinality(String),
  op     LowCardinality(String),
  c      UInt64
)
ENGINE = SummingMergeTree
PARTITION BY toDate(t_hour)
ORDER BY (t_hour, ns, event_type, op)
TTL toDate(t_min) + INTERVAL 180 DAY;

CREATE MATERIALIZED VIEW mv_minute_to_hour
TO fact_events_hour AS
SELECT toStartOfHour(t_min) AS t_hour, ns, event_type, op, sum(c) AS c
FROM fact_events_minute
GROUP BY t_hour, ns, event_type, op;

CREATE TABLE fact_latency_minute (
  t_min DateTime,
  ns    LowCardinality(String),
  p50_ms UInt32,
  p95_ms UInt32
)
ENGINE = ReplacingMergeTree
PARTITION BY toDate(t_min)
ORDER BY (t_min, ns)
TTL toDate(t_min) + INTERVAL 180 DAY;

CREATE MATERIALIZED VIEW mv_parsed_to_latency_minute
TO fact_latency_minute AS
SELECT
  toStartOfMinute(ts_ingest) AS t_min,
  ns,
  quantileTiming(0.50)(dateDiff('millisecond', ts_event, ts_ingest)) AS p50_ms,
  quantileTiming(0.95)(dateDiff('millisecond', ts_event, ts_ingest)) AS p95_ms
FROM parsed_mongodb      -- repeat per source or UNION ALL a parsed_all view (see below)
WHERE ts_event IS NOT NULL
GROUP BY t_min, ns;

CREATE TABLE fact_errors_minute (
  t_min DateTime,
  ns    LowCardinality(String),
  c     UInt64
)
ENGINE = SummingMergeTree
PARTITION BY toDate(t_min)
ORDER BY (t_min, ns)
TTL toDate(t_min) + INTERVAL 180 DAY;

CREATE MATERIALIZED VIEW mv_parsed_to_errors_minute
TO fact_errors_minute AS
SELECT toStartOfMinute(ts_ingest) AS t_min, ns, count() AS c
FROM parsed_mongodb      -- repeat per source or UNION ALL a parsed_all view (see below)
WHERE lower(severity) IN ('error','warn') OR op = 'd'
GROUP BY t_min, ns;

CREATE OR REPLACE VIEW parsed_all AS
SELECT ts_event, ts_ingest, source, event_type, ns, event_id, severity, op, status, message, payload_json
FROM parsed_mongodb
-- UNION ALL
-- SELECT ts_event, ts_ingest, source, event_type, ns, event_id, severity, op, status, message, payload_json
-- FROM parsed_servicenow
-- UNION ALL
-- SELECT ts_event, ts_ingest, source, event_type, ns, event_id, severity, op, status, message, payload_json
-- FROM parsed_splunk
/* …add more as you onboard them */
;

CREATE OR REPLACE VIEW vw_events AS
SELECT
  ts_event,
  ts_ingest,
  source,
  ns,
  event_type,
  op,
  coalesce(status,'') AS status,
  coalesce(severity,'') AS severity,
  event_id,
  message
FROM parsed_all;

CREATE OR REPLACE VIEW vw_alerts AS
SELECT
  ts_event,
  ts_ingest,
  source,
  ns,
  event_id,
  event_type,
  severity,
  status,
  message
FROM parsed_all
WHERE event_type IN ('alert','incident')    -- map upstreams to this canon
   OR (source IN ('splunk','dynatrace') AND lower(severity) IN ('warn','error','critical'));

CREATE OR REPLACE VIEW vw_changes AS
SELECT
  ts_event,
  ts_ingest,
  source,
  ns,
  event_id,
  op,
  status,
  JSON_VALUE(payload_json, '$.commit_sha') AS commit_sha,
  JSON_VALUE(payload_json, '$.ticket_id') AS ticket_id,
  message
FROM parsed_all
WHERE event_type IN ('cdc','commit','deploy','change');

-- Tiny sidecar keyed by (ns, event_type, op, status) with a rolling probability/score

-- CREATE TABLE enrich_surprisal_24h (
--   ns LowCardinality(String),
--   event_type LowCardinality(String),
--   op LowCardinality(String),
--   status LowCardinality(String),
--   asof_ts DateTime,
--   surprisal Float32
-- )
-- ENGINE = ReplacingMergeTree(asof_ts)
-- ORDER BY (ns, event_type, op, status);

-- CREATE OR REPLACE VIEW vw_events_enriched AS
-- SELECT e.*, coalesce(s.surprisal, 0.0) AS surprisal_24h
-- FROM vw_events e
-- LEFT JOIN enrich_surprisal_24h s
--   ON s.ns=e.ns AND s.event_type=e.event_type AND s.op=e.op AND s.status=e.status;

-- Simple semantic cover for dashboards

CREATE OR REPLACE VIEW vw_events_rate_minute AS
SELECT t_min, ns, event_type, op, c
FROM fact_events_minute;

CREATE OR REPLACE VIEW vw_latency_p95_minute AS
SELECT t_min, ns, p95_ms
FROM fact_latency_minute;

-- CREATE TABLE IF NOT EXISTS fact_order_failures_minute (
--   t_min DateTime,
--   ns LowCardinality(String),
--   c UInt64
-- )
-- ENGINE = SummingMergeTree
-- PARTITION BY toDate(t_min)
-- ORDER BY (t_min, ns)
-- TTL toDate(t_min) + INTERVAL 365 DAY;

-- CREATE MATERIALIZED VIEW IF NOT EXISTS mv_parsed_to_fact_order_failures_minute
-- TO fact_order_failures_minute AS
-- SELECT
--   toStartOfMinute(ts_ingest) AS t_min,
--   ns,
--   count() AS c
-- FROM parsed_mongodb
-- WHERE lower(severity) IN ('error','warn')
--    OR lower(JSON_VALUE(payload_json,'$.status')) IN ('payment_failed','failed')
-- GROUP BY t_min, ns;

-- CREATE TABLE IF NOT EXISTS fact_jira_start_hour (
--   t_hour DateTime,
--   ns LowCardinality(String),
--   c UInt64
-- )
-- ENGINE = SummingMergeTree
-- PARTITION BY toDate(t_hour)
-- ORDER BY (t_hour, ns)
-- TTL toDate(t_hour) + INTERVAL 2 YEAR;

-- CREATE MATERIALIZED VIEW IF NOT EXISTS mv_parsed_to_fact_jira_start_hour
-- TO fact_jira_start_hour AS
-- SELECT
--   toStartOfHour(ts_event) AS t_hour,
--   ns,
--   count() AS c
-- FROM parsed_jira
-- WHERE event_type='ticket_transition' AND lower(status)='in progress'
-- GROUP BY t_hour, ns;

-- Keyed join (safe in CH)

-- Git ↔ Jira by ticket_id
-- SELECT
--   g.commit_ts, j.ts_event AS ticket_ts, j.ticket_id, g.commit_sha, g.author
-- FROM parsed_git g
-- INNER JOIN parsed_jira j USING (ticket_id)
-- WHERE g.commit_ts BETWEEN now()-INTERVAL 7 DAY AND now();

-- Time-window join (OK in CH, but better for ML at scale)

-- Minute buckets, 30m lookahead for incidents after deploys
-- WITH
--   (SELECT t_min, service, sum(c) AS deploys FROM fact_deploys_minute GROUP BY t_min, service) d,
--   (SELECT t_min, service, sum(c) AS incidents FROM fact_incidents_minute GROUP BY t_min, service) i
-- SELECT
--   d.t_min, d.service,
--   deploys,
--   sumIf(i.incidents, i.t_min BETWEEN d.t_min AND d.t_min + INTERVAL 30 MINUTE) AS incidents_next_30m
-- FROM d
-- LEFT JOIN i ON i.service = d.service
-- GROUP BY d.t_min, d.service, deploys
-- ORDER BY d.t_min;
