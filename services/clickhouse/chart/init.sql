-- ClickHouse Initialization Script
-- Creates the cdc_events table for immutable event storage

-- Create database
CREATE DATABASE IF NOT EXISTS cdc_events;

USE cdc_events;

-- Create the immutable event store table
CREATE TABLE IF NOT EXISTS cdc_events (
    event_time DateTime64(3) DEFAULT now64(3),
    event_date Date DEFAULT toDate(event_time),
    database String,
    schema String,
    table_name String,
    primary_key String,
    operation Enum8('r' = 1, 'c' = 2, 'u' = 3, 'd' = 4),
    before_json String,
    after_json String,
    transaction_id String,
    lsn String,
    raw_event String,
    ingested_at DateTime64(3) DEFAULT now64(3)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_date, table_name, primary_key, event_time)
TTL event_date + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;

-- Create Kafka engine table to consume CDC events from Kafka
CREATE TABLE IF NOT EXISTS cdc_events_queue (
    message String
) ENGINE = Kafka
SETTINGS 
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'postgres.public.mara',
    kafka_group_name = 'clickhouse-consumer',
    kafka_format = 'JSONAsString',
    kafka_num_consumers = 1;

-- Create materialized view to parse Debezium envelope and persist events
CREATE MATERIALIZED VIEW IF NOT EXISTS cdc_events_consumer TO cdc_events AS
SELECT
    -- Extract timestamp
    fromUnixTimestamp64Milli(
        CAST(JSONExtractString(message, 'ts_ms') AS Int64)
    ) AS event_time,
    toDate(event_time) AS event_date,
    
    -- Extract source metadata
    JSONExtractString(message, 'source', 'db') AS database,
    JSONExtractString(message, 'source', 'schema') AS schema,
    JSONExtractString(message, 'source', 'table') AS table_name,
    
    -- Build primary key from after/before data
    JSONExtractRaw(
        COALESCE(
            JSONExtractRaw(message, 'after'),
            JSONExtractRaw(message, 'before')
        )
    ) AS primary_key,
    
    -- Extract operation (r=read, c=create, u=update, d=delete) and cast to Enum8
    CAST(JSONExtractString(message, 'op') AS Enum8('r'=1, 'c'=2, 'u'=3, 'd'=4)) AS operation,
    
    -- Extract before/after states
    JSONExtractRaw(message, 'before') AS before_json,
    JSONExtractRaw(message, 'after') AS after_json,
    
    -- Extract transaction metadata
    JSONExtractString(message, 'source', 'txId') AS transaction_id,
    JSONExtractString(message, 'source', 'lsn') AS lsn,
    
    -- Store raw event
    message AS raw_event,
    
    now64(3) AS ingested_at
FROM cdc_events_queue;

-- Create a view for easier querying
CREATE VIEW IF NOT EXISTS cdc_events_readable AS
SELECT
    event_time,
    database,
    schema,
    table_name,
    primary_key,
    CASE operation
        WHEN 'r' THEN 'READ (Snapshot)'
        WHEN 'c' THEN 'CREATE'
        WHEN 'u' THEN 'UPDATE'
        WHEN 'd' THEN 'DELETE'
    END AS operation_type,
    before_json,
    after_json,
    transaction_id,
    lsn,
    ingested_at
FROM cdc_events;

-- ML: Anomaly Detection Results Table
CREATE TABLE IF NOT EXISTS anomaly_detections (
    detection_id UUID DEFAULT generateUUIDv4(),
    event_time DateTime64(3),
    table_name String,
    material_id String,
    primary_key String,
    anomaly_score Float64,
    is_anomaly UInt8,
    model_version String,
    features_json String,
    detected_at DateTime64(3) DEFAULT now64(3)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(detected_at)
ORDER BY (toDate(detected_at), table_name, material_id, detected_at)
TTL toDateTime(detected_at) + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;

-- ML: Job Checkpoint Table
CREATE TABLE IF NOT EXISTS ml_job_checkpoints (
    job_name String,
    last_processed_timestamp DateTime64(3),
    processed_count UInt64,
    anomalies_detected UInt64,
    updated_at DateTime64(3) DEFAULT now64(3)
) ENGINE = ReplacingMergeTree(updated_at)
ORDER BY job_name
SETTINGS index_granularity = 8192;

-- ML: View combining anomalies with full CDC event details
CREATE VIEW IF NOT EXISTS anomalies_with_details AS
SELECT
    a.detection_id,
    a.event_time,
    a.detected_at,
    a.table_name,
    a.material_id,
    a.anomaly_score,
    a.is_anomaly,
    a.model_version,
    a.features_json,
    e.operation,
    e.before_json,
    e.after_json,
    e.ingested_at AS event_ingested_at
FROM anomaly_detections a
LEFT JOIN cdc_events e ON (
    a.primary_key = e.primary_key 
    AND a.event_time = e.event_time
);

-- Create a materialized view for event statistics
CREATE MATERIALIZED VIEW IF NOT EXISTS cdc_events_stats
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_date, table_name, operation)
AS SELECT
    event_date,
    table_name,
    operation,
    count() as event_count
FROM cdc_events
GROUP BY event_date, table_name, operation;

-- Create a view for timeline queries (by primary key)
CREATE VIEW IF NOT EXISTS cdc_timeline AS
SELECT
    table_name,
    primary_key,
    event_time,
    operation,
    after_json,
    before_json
FROM cdc_events
ORDER BY primary_key, event_time;

-- Example queries (commented out - for reference)
/*
-- Query 1: Show all CDC events
SELECT * FROM cdc_events_readable ORDER BY event_time DESC LIMIT 100;

-- Query 2: Show timeline for a specific record
SELECT * FROM cdc_timeline 
WHERE table_name = 'mara' 
  AND primary_key = '{"mandt":"800","matnr":"IAD-5006"}'
ORDER BY event_time;

-- Query 3: Event statistics by table and operation
SELECT 
    event_date,
    table_name,
    operation_type,
    count() as events
FROM cdc_events_readable
GROUP BY event_date, table_name, operation_type
ORDER BY event_date DESC, events DESC;

-- Query 4: Recent events (last 24 hours)
SELECT * FROM cdc_events_readable
WHERE event_time >= now() - INTERVAL 1 DAY
ORDER BY event_time DESC;

-- Query 5: Window delta - changes between two timestamps
SELECT 
    table_name,
    primary_key,
    min(event_time) as first_change,
    max(event_time) as last_change,
    count() as change_count,
    groupArray(operation) as operations
FROM cdc_events
WHERE event_time BETWEEN '2026-08-06 00:00:00' AND '2026-08-06 23:59:59'
GROUP BY table_name, primary_key
HAVING change_count > 1;
*/
