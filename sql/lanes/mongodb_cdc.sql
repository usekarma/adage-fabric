-- Fabric Lane Template (per-lane objects + writers to global rollups)
-- Variables (envsubst): adage demo mongodb cdc 1
-- Topic: adage.demo.mongodb.cdc.v1

-------------------------------
-- 0) Safety drops (idempotent)
-------------------------------
DROP VIEW IF EXISTS mv_kafka_to_raw_mongodb_cdc;
DROP TABLE IF EXISTS kafka_mongodb_cdc;

DROP VIEW IF EXISTS mv_raw_to_parsed_mongodb_cdc;
DROP TABLE IF EXISTS parsed_mongodb_cdc;
DROP TABLE IF EXISTS raw_mongodb_cdc;

DROP VIEW IF EXISTS mv_parsed_to_fact_minute_mongodb_cdc;
DROP TABLE IF EXISTS fact_events_minute_mongodb_cdc;

DROP VIEW IF EXISTS mv_parsed_to_latency_minute_mongodb_cdc;
DROP TABLE IF EXISTS fact_latency_minute_mongodb_cdc;

-- Optional, domain-specific per-lane facts (enable as applicable)
DROP VIEW IF EXISTS mv_parsed_to_fact_order_failures_minute_mongodb_cdc;
DROP TABLE IF EXISTS fact_order_failures_minute_mongodb_cdc;

DROP VIEW IF EXISTS mv_parsed_to_fact_jira_start_hour_mongodb_cdc;
DROP TABLE IF EXISTS fact_jira_start_hour_mongodb_cdc;

-- Writer MVs to global rollups (assumes shared tables exist)
DROP VIEW IF EXISTS mv_fact_minute_mongodb_cdc_to_all;
DROP VIEW IF EXISTS mv_latency_minute_mongodb_cdc_to_all;
DROP VIEW IF EXISTS mv_order_failures_minute_mongodb_cdc_to_all;
DROP VIEW IF EXISTS mv_jira_start_hour_mongodb_cdc_to_all;

--------------------------------------------
-- 1) Kafka source (preserve full JSON line)
--    Use JSONAsString so we keep the raw payload as 'value_json'.
--------------------------------------------
CREATE TABLE kafka_mongodb_cdc
(
  value_json String
)
ENGINE = Kafka
SETTINGS
  kafka_broker_list   = 'redpanda:9092',
  kafka_topic_list    = 'adage.demo.mongodb.cdc.v1',
  kafka_group_name    = 'fabric_mongodb_cdc',
  kafka_format        = 'JSONAsString',
  kafka_row_delimiter = '\n',
  kafka_num_consumers = 1;

-----------------------------
-- 2) RAW landing (per-lane)
-----------------------------
CREATE TABLE IF NOT EXISTS raw_mongodb_cdc
(
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

-- Kafka → RAW (preserve full JSON via value_json column)
CREATE MATERIALIZED VIEW mv_kafka_to_raw_mongodb_cdc
TO raw_mongodb_cdc
AS
SELECT
  _topic     AS topic,
  _partition AS partition_id,
  _offset    AS offset,
  ifNull(_key,'') AS key,
  value_json
FROM kafka_mongodb_cdc;

----------------------------------
-- 3) PARSED (centralized JSON)
----------------------------------
CREATE TABLE IF NOT EXISTS parsed_mongodb_cdc
(
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

-- RAW → PARSED
CREATE MATERIALIZED VIEW mv_raw_to_parsed_mongodb_cdc
TO parsed_mongodb_cdc
AS
SELECT
  parseDateTime64BestEffort(JSONExtractString(value_json,'ts_event')) AS ts_event,
  now64(3) AS ts_ingest,
  coalesce(JSONExtractString(value_json,'source'),'mongodb_cdc')     AS source,
  coalesce(JSONExtractString(value_json,'event_type'),'')                   AS event_type,
  coalesce(JSONExtractString(value_json,'ns'),'')                           AS ns,
  coalesce(JSONExtractString(value_json,'event_id'), JSONExtractString(value_json,'_id'), toString(cityHash64(value_json))) AS event_id,
  lower(coalesce(JSONExtractString(value_json,'severity'), ''))            AS severity,
  lower(coalesce(JSONExtractString(value_json,'op'), ''))                  AS op,
  coalesce(JSONExtractString(value_json,'payload.status'), '')             AS status,
  left(coalesce(JSONExtractString(value_json,'payload.message'), ''), 2000) AS message,
  coalesce(JSONExtractRaw(value_json,'payload'), value_json)               AS payload_json
FROM raw_mongodb_cdc;

-------------------------------
-- 4) FACTS (per-lane basics)
-------------------------------

-- Per-minute event counts
CREATE TABLE IF NOT EXISTS fact_events_minute_mongodb_cdc
(
  t_min DateTime,
  ns LowCardinality(String),
  event_type LowCardinality(String),
  op LowCardinality(String),
  c UInt64
)
ENGINE = SummingMergeTree
PARTITION BY toDate(t_min)
ORDER BY (t_min, ns, event_type, op)
TTL toDate(t_min) + INTERVAL 365 DAY;

CREATE MATERIALIZED VIEW mv_parsed_to_fact_minute_mongodb_cdc
TO fact_events_minute_mongodb_cdc AS
SELECT
  toStartOfMinute(ts_ingest) AS t_min,
  ns, event_type, op,
  count() AS c
FROM parsed_mongodb_cdc
GROUP BY t_min, ns, event_type, op;

-- Per-minute ingest latency percentiles
CREATE TABLE IF NOT EXISTS fact_latency_minute_mongodb_cdc
(
  t_min DateTime,
  ns LowCardinality(String),
  p50_ms UInt32,
  p95_ms UInt32
)
ENGINE = ReplacingMergeTree
PARTITION BY toDate(t_min)
ORDER BY (t_min, ns)
TTL toDate(t_min) + INTERVAL 180 DAY;

CREATE MATERIALIZED VIEW mv_parsed_to_latency_minute_mongodb_cdc
TO fact_latency_minute_mongodb_cdc AS
SELECT
  toStartOfMinute(ts_ingest) AS t_min,
  ns,
  quantileTiming(0.50)(dateDiff('millisecond', ts_event, ts_ingest)) AS p50_ms,
  quantileTiming(0.95)(dateDiff('millisecond', ts_event, ts_ingest)) AS p95_ms
FROM parsed_mongodb_cdc
WHERE ts_event IS NOT NULL
GROUP BY t_min, ns;

-- Optional domain fact: Order failures per minute (enable for Mongo CDC-like lanes)
/*
CREATE TABLE IF NOT EXISTS fact_order_failures_minute_mongodb_cdc
(
  t_min DateTime,
  ns LowCardinality(String),
  c UInt64
)
ENGINE = SummingMergeTree
PARTITION BY toDate(t_min)
ORDER BY (t_min, ns)
TTL toDate(t_min) + INTERVAL 365 DAY;

CREATE MATERIALIZED VIEW mv_parsed_to_fact_order_failures_minute_mongodb_cdc
TO fact_order_failures_minute_mongodb_cdc AS
SELECT
  toStartOfMinute(ts_ingest) AS t_min,
  ns,
  count() AS c
FROM parsed_mongodb_cdc
WHERE lower(severity) IN ('error','warn')
   OR lower(JSONExtractString(payload_json,'status')) IN ('payment_failed','failed')
GROUP BY t_min, ns;
*/

-- Optional domain fact: Jira tickets entering "In Progress" per hour (enable for Jira lanes)
/*
CREATE TABLE IF NOT EXISTS fact_jira_start_hour_mongodb_cdc
(
  t_hour DateTime,
  ns LowCardinality(String),
  c UInt64
)
ENGINE = SummingMergeTree
PARTITION BY toDate(t_hour)
ORDER BY (t_hour, ns)
TTL toDate(t_hour) + INTERVAL 2 YEAR;

CREATE MATERIALIZED VIEW mv_parsed_to_fact_jira_start_hour_mongodb_cdc
TO fact_jira_start_hour_mongodb_cdc AS
SELECT
  toStartOfHour(ts_event) AS t_hour,
  ns,
  count() AS c
FROM parsed_mongodb_cdc
WHERE event_type='ticket_transition' AND lower(status)='in progress'
GROUP BY t_hour, ns;
*/

---------------------------------------------------
-- 5) Writer MVs into global rollup tables (Option B)
--    Requires shared global tables to exist already.
---------------------------------------------------
CREATE MATERIALIZED VIEW mv_fact_minute_mongodb_cdc_to_all
TO fact_events_minute_all AS
SELECT t_min, ns, event_type, op, c, 'mongodb_cdc' AS lane
FROM fact_events_minute_mongodb_cdc;

CREATE MATERIALIZED VIEW mv_latency_minute_mongodb_cdc_to_all
TO fact_latency_minute_all AS
SELECT t_min, ns, p50_ms, p95_ms, 'mongodb_cdc' AS lane
FROM fact_latency_minute_mongodb_cdc;
