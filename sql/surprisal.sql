-- Tiny sidecar keyed by (ns, event_type, op, status) with a rolling probability/score

CREATE TABLE enrich_surprisal_24h (
  ns LowCardinality(String),
  event_type LowCardinality(String),
  op LowCardinality(String),
  status LowCardinality(String),
  asof_ts DateTime,
  surprisal Float32
)
ENGINE = ReplacingMergeTree(asof_ts)
ORDER BY (ns, event_type, op, status);

CREATE OR REPLACE VIEW vw_events_enriched AS
SELECT e.*, coalesce(s.surprisal, 0.0) AS surprisal_24h
FROM vw_events e
LEFT JOIN enrich_surprisal_24h s
  ON s.ns=e.ns AND s.event_type=e.event_type AND s.op=e.op AND s.status=e.status;

