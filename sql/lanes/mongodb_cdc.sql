-- Fabric Lane Template (per-lane objects + writers to global rollups)
-- Variables (envsubst): adage demo mongodb cdc 1
-- Topic: adage.demo.mongodb.cdc.v1

-------------------------------
-- 0) Safety drops (idempotent)
-------------------------------
DROP VIEW IF EXISTS mv_kafka_to_parsed_mongodb_cdc;
DROP TABLE IF EXISTS kafka_mongodb_cdc;

DROP TABLE IF EXISTS parsed_mongodb_cdc;

DROP VIEW IF EXISTS mv_parsed_to_fact_minute_mongodb_cdc;
DROP TABLE IF EXISTS fact_events_minute_mongodb_cdc;

DROP VIEW IF EXISTS mv_parsed_to_latency_minute_mongodb_cdc;
DROP TABLE IF EXISTS fact_latency_minute_mongodb_cdc;

-- Writer MVs to global rollups (assumes shared tables exist)
DROP VIEW IF EXISTS mv_fact_minute_mongodb_cdc_to_all;
DROP VIEW IF EXISTS mv_latency_minute_mongodb_cdc_to_all;

--------------------------------------------
-- 1) Kafka source (top-level schema guard)
--------------------------------------------
CREATE TABLE kafka_mongodb_cdc
(
  source      LowCardinality(String),
  event_type  LowCardinality(String),
  ns          LowCardinality(String),
  event_id    String,
  ts_event    String,                 -- parse to DateTime64 in MV
  op          LowCardinality(String),
  severity    LowCardinality(String)
)
ENGINE = Kafka
SETTINGS
  kafka_broker_list = 'redpanda:29092,redpanda:9092',
  kafka_topic_list               = 'adage.demo.mongodb.cdc.v1',
  kafka_group_name               = 'fabric_mongodb_cdc_v1',  -- bump VERSION to reset offsets
  kafka_format                   = 'JSONEachRow',
  kafka_num_consumers            = 1,
  kafka_skip_broken_messages     = 1000000,
  input_format_skip_unknown_fields = 1;

----------------------------------
-- 2) PARSED (direct from Kafka)
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

-- Kafka → PARSED (direct ingest)
CREATE MATERIALIZED VIEW mv_kafka_to_parsed_mongodb_cdc
TO parsed_mongodb_cdc AS
SELECT
  ifNull(toDateTime64(parseDateTimeBestEffortOrNull(ts_event), 3), now64(3)) AS ts_event,
  now64(3) AS ts_ingest,
  'mongodb_cdc' AS source,
  event_type,
  ns,
  event_id,
  lower(ifNull(severity,'')) AS severity,
  ifNull(op,'')              AS op,
  '' AS status,
  '' AS message,
  '{}' AS payload_json
FROM kafka_mongodb_cdc;

-------------------------------
-- 3) FACTS (per-lane basics)
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

---------------------------------------------------
-- 4) Writer MVs into global rollup tables
---------------------------------------------------
CREATE MATERIALIZED VIEW mv_fact_minute_mongodb_cdc_to_all
TO fact_events_minute_all AS
SELECT t_min, ns, event_type, op, c, 'mongodb_cdc' AS lane
FROM fact_events_minute_mongodb_cdc;

CREATE MATERIALIZED VIEW mv_latency_minute_mongodb_cdc_to_all
TO fact_latency_minute_all AS
SELECT t_min, ns, p50_ms, p95_ms, 'mongodb_cdc' AS lane
FROM fact_latency_minute_mongodb_cdc;
