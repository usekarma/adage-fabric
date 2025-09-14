-- Global rollups (targets for writer MVs)
CREATE TABLE IF NOT EXISTS fact_events_minute_all (
  t_min DateTime, ns LowCardinality(String),
  event_type LowCardinality(String), op LowCardinality(String),
  c UInt64, lane LowCardinality(String)
) ENGINE = SummingMergeTree
PARTITION BY toDate(t_min)
ORDER BY (t_min, ns, event_type, op, lane)
TTL toDate(t_min) + INTERVAL 365 DAY;

CREATE TABLE IF NOT EXISTS fact_latency_minute_all (
  t_min DateTime, ns LowCardinality(String),
  p50_ms UInt32, p95_ms UInt32, lane LowCardinality(String)
) ENGINE = ReplacingMergeTree
PARTITION BY toDate(t_min)
ORDER BY (t_min, ns, lane)
TTL toDate(t_min) + INTERVAL 180 DAY;

-- Optional domain rollups (only if you enable them in lanes)
CREATE TABLE IF NOT EXISTS fact_order_failures_minute_all (
  t_min DateTime, ns LowCardinality(String),
  c UInt64, lane LowCardinality(String)
) ENGINE = SummingMergeTree
PARTITION BY toDate(t_min)
ORDER BY (t_min, ns, lane)
TTL toDate(t_min) + INTERVAL 365 DAY;

CREATE TABLE IF NOT EXISTS fact_jira_start_hour_all (
  t_hour DateTime, ns LowCardinality(String),
  c UInt64, lane LowCardinality(String)
) ENGINE = SummingMergeTree
PARTITION BY toDate(t_hour)
ORDER BY (t_hour, ns, lane)
TTL toDate(t_hour) + INTERVAL 2 YEAR;
