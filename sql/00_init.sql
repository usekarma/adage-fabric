-- Kafka source (same as earlier demo; topic paramized below by scripts if you prefer)
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
  c UInt64
)
ENGINE = SummingMergeTree
PARTITION BY toDate(t_min)
ORDER BY (t_min, ns, event_type);

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_parsed_to_facts_minute
TO facts_events_minute AS
SELECT toStartOfMinute(ts_ingest) AS t_min, ns, event_type, count() AS c
FROM parsed_mongodb
GROUP BY t_min, ns, event_type;
