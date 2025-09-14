-- Shared cross-source views: run AFTER all lanes are created
-- Edit the UNION ALL list to include your parsed tables.

/* Replace the sample below with your lanes */
DROP VIEW IF EXISTS parsed_all;
CREATE VIEW parsed_all AS
SELECT ts_event, ts_ingest, source, event_type, ns, event_id, severity, op, status, message, payload_json
FROM parsed_mongodb_cdc
/* UNION ALL
SELECT ts_event, ts_ingest, source, event_type, ns, event_id, severity, op, status, message, payload_json FROM parsed_jira_events
UNION ALL
SELECT ts_event, ts_ingest, source, event_type, ns, event_id, severity, op, status, message, payload_json FROM parsed_splunk_alerts
... add more lanes here ... */
;

DROP VIEW IF EXISTS vw_events;
CREATE VIEW vw_events AS
SELECT
  ts_event, ts_ingest, source, ns, event_type, op,
  coalesce(status,'') AS status,
  coalesce(severity,'') AS severity,
  event_id, message
FROM parsed_all;

DROP VIEW IF EXISTS vw_alerts;
CREATE VIEW vw_alerts AS
SELECT
  ts_event, ts_ingest, source, ns, event_id, event_type, severity, status, message
FROM parsed_all
WHERE event_type IN ('alert','incident')
   OR (source IN ('splunk','dynatrace') AND lower(severity) IN ('warn','error','critical'));

DROP VIEW IF EXISTS vw_changes;
CREATE VIEW vw_changes AS
SELECT
  ts_event, ts_ingest, source, ns, event_id, op, status,
  JSONExtractString(payload_json, 'commit_sha') AS commit_sha,
  JSONExtractString(payload_json, 'ticket_id')  AS ticket_id,
  message
FROM parsed_all
WHERE event_type IN ('cdc','commit','deploy','change');

-- Events/min rate across all lanes
CREATE OR REPLACE VIEW vw_events_rate_minute AS
SELECT t_min, ns, event_type, op, c, lane
FROM fact_events_minute_all;

-- Latency p95 across all lanes
CREATE OR REPLACE VIEW vw_latency_p95_minute AS
SELECT t_min, ns, p95_ms, lane
FROM fact_latency_minute_all;
