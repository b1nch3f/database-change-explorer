# Database Change Explorer - Technical Deep Dive

This document provides a detailed technical explanation of how CDC (Change Data Capture) events flow through the entire pipeline, from PostgreSQL to the Tabix UI.

---

## **Architecture Overview**

```
PostgreSQL (pgAdmin)
    ↓ Logical Replication (WAL)
Debezium Connector
    ↓ Kafka Connect
Kafka/Redpanda
    ↓ Topic: postgres.public.mara
ClickHouse Kafka Engine
    ↓ Materialized View (Parsing)
ClickHouse cdc_events Table
    ↓ SQL Queries
Tabix Web UI
```

---

## **Phase 1: PostgreSQL Write-Ahead Log (WAL)**

### How PostgreSQL Captures Changes

**Configuration:**
```ini
wal_level = logical              # Enables logical decoding
max_wal_senders = 10            # Max concurrent replication connections
max_replication_slots = 10      # Max replication slots
```

**What Happens When You Execute SQL:**

1. **Transaction Begins:**
   ```sql
   INSERT INTO mara (mandt, matnr, mtart, ersda, ernam) 
   VALUES ('100', 'DEMO001', 'ROH', '20260807', 'DEMOUSER');
   ```

2. **PostgreSQL Writes to WAL (Binary Format):**
   - Every INSERT/UPDATE/DELETE is written to WAL **before** committing
   - WAL ensures ACID durability
   - Binary format includes:
     - Transaction ID (txId)
     - Log Sequence Number (LSN) - position in WAL
     - Table OID (internal table identifier)
     - Tuple data (row values)

3. **Commit:**
   - Transaction commits
   - WAL entry marked as committed
   - Data becomes visible to other transactions

**WAL Structure:**
```
LSN: 0/195B2B0
TxID: 12345
Operation: INSERT
Table: public.mara (OID: 16385)
Tuple: [mandt='100', matnr='DEMO001', mtart='ROH', ...]
Commit: true
```

---

## **Phase 2: Debezium Logical Decoding**

### How Debezium Reads the WAL

**Replication Slot:**
- Name: `debezium_mara`
- Plugin: `pgoutput` (PostgreSQL built-in)
- Type: Logical replication

**Connection Process:**

1. **Debezium Connects via Replication Protocol:**
   ```
   Port: 5432
   Protocol: Streaming Replication (not JDBC)
   User: dbuser (needs replication permission)
   ```

2. **Creates/Uses Replication Slot:**
   ```sql
   SELECT * FROM pg_replication_slots WHERE slot_name = 'debezium_mara';
   ```
   Output:
   ```
   slot_name     | debezium_mara
   plugin        | pgoutput
   slot_type     | logical
   active        | t
   restart_lsn   | 0/195B2B0  -- Current position
   ```

3. **Starts Streaming:**
   ```sql
   START_REPLICATION SLOT debezium_mara LOGICAL 0/195B2B0
   ```

**pgoutput Plugin Decodes WAL:**
- Converts binary WAL entries to structured messages
- Filters by configured tables: `table.include.list = public.mara`
- Provides before/after row states
- Groups changes by transaction

**Decoded Message (Internal Format):**
```
BEGIN txid=12345 timestamp=2026-08-08T13:38:19.452Z
TABLE public.mara: INSERT
  mandt = '100'
  matnr = 'DEMO001'
  mtart = 'ROH'
  ersda = '20260807'
  ernam = 'DEMOUSER'
  [... 15 more columns ...]
COMMIT txid=12345
```

---

## **Phase 3: Kafka Connect Framework**

### Debezium Connector Configuration

**Connector Properties (`postgres-connector.json`):**
```json
{
  "name": "postgres-mara-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "postgres",
    "database.port": "5432",
    "database.user": "dbuser",
    "database.password": "dbpass123",
    "database.dbname": "sourcedb",
    "table.include.list": "public.mara",
    "plugin.name": "pgoutput",
    "slot.name": "debezium_mara",
    "topic.prefix": "postgres",
    "snapshot.mode": "initial"
  }
}
```

**Kafka Connect Does:**
1. Manages connector lifecycle (start/stop/restart)
2. Handles offsets (tracks last processed LSN)
3. Provides REST API for management
4. Converts decoded WAL to JSON (Debezium format)

**Debezium Envelope Format:**
```json
{
  "schema": null,
  "payload": null,
  "before": null,
  "after": {
    "mandt": "100",
    "matnr": "DEMO001",
    "ersda": "20260807",
    "ernam": "DEMOUSER",
    "laeda": null,
    "aenam": null,
    "mtart": "ROH",
    "matkl": null,
    "meins": null,
    "brgew": null,
    "ntgew": null,
    "gewei": null,
    "volum": null,
    "voleh": null,
    "laeng": null,
    "breit": null,
    "hoehe": null,
    "meabm": null,
    "bismt": null,
    "lvorm": null
  },
  "source": {
    "version": "2.7.0.Final",
    "connector": "postgresql",
    "name": "postgres",
    "ts_ms": 1723122899452,
    "snapshot": "false",
    "db": "sourcedb",
    "sequence": "[\"24557016\",\"24557016\"]",
    "schema": "public",
    "table": "mara",
    "txId": 12345,
    "lsn": 24557016,
    "xmin": null
  },
  "op": "c",
  "ts_ms": 1723122899687,
  "transaction": null
}
```

**Key Fields:**
- `op`: Operation type (`r`=read/snapshot, `c`=create, `u`=update, `d`=delete)
- `before`: Row state before change (null for INSERT, populated for UPDATE/DELETE)
- `after`: Row state after change (null for DELETE, populated for INSERT/UPDATE)
- `source`: Metadata (database, table, LSN, transaction ID, timestamp)
- `ts_ms`: Event timestamp (milliseconds since epoch)

**Topic Naming:**
- Pattern: `{topic.prefix}.{schema}.{table}`
- Result: `postgres.public.mara`

---

## **Phase 4: Kafka/Redpanda Topic Storage**

### Message Broker Details

**Redpanda Configuration:**
```yaml
image: docker.redpanda.com/redpandadata/redpanda:v24.2.4
command:
  - /usr/bin/rpk
  - redpanda
  - start
  - --smp 1                    # Single CPU
  - --memory 512M              # Memory limit
  - --overprovisioned          # Dev mode
  - --kafka-addr PLAINTEXT://0.0.0.0:9092
```

**Topic Structure:**
- **Topic Name:** `postgres.public.mara`
- **Partitions:** 1 (default)
- **Replication Factor:** 1 (single broker)
- **Retention:** Unlimited (until disk full)
- **Format:** JSON strings

**Message Storage:**
Each CDC event is stored as a separate Kafka message:

```
Offset: 0
Timestamp: 2026-08-08T13:38:19.452Z
Key: {"schema":null,"payload":{"mandt":"100","matnr":"DEMO001"}}
Value: {... full Debezium JSON envelope ...}
```

**Consumer Groups:**
- `clickhouse-consumer`: ClickHouse Kafka engine
- Each consumer group tracks its own offset independently

**Why Kafka?**
1. **Decoupling:** PostgreSQL and ClickHouse don't know about each other
2. **Buffering:** If ClickHouse is down, events accumulate in Kafka
3. **Replay:** Can reprocess events from any offset
4. **Multiple Consumers:** Could add more consumers (e.g., Elasticsearch, S3)
5. **Durability:** Events persisted to disk

---

## **Phase 5: ClickHouse Kafka Engine** 🚀

### This is Where the Magic Happens!

**Table Definition (`clickhouse/init.sql`):**
```sql
CREATE TABLE IF NOT EXISTS cdc_events_queue (
    message String
) ENGINE = Kafka
SETTINGS 
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'postgres.public.mara',
    kafka_group_name = 'clickhouse-consumer',
    kafka_format = 'JSONAsString',
    kafka_num_consumers = 1;
```

**How Kafka Engine Works:**

### 1. **Background Polling**
- ClickHouse runs a background thread that polls Kafka every few seconds
- Uses Kafka Consumer Protocol
- Commits offsets automatically after processing
- Handles reconnections and failover

### 2. **Message Consumption**
- Fetches messages in batches (default: 65536 messages or 1MB)
- Stores raw JSON string in the `message` column
- **Table appears empty when queried** - messages are immediately consumed by materialized views

### 3. **Zero Configuration Consumer**
```sql
-- This query returns nothing:
SELECT * FROM cdc_events_queue LIMIT 10;

-- Why? Messages are instantly pulled by the materialized view!
```

**Internal Flow:**
```
Kafka Topic: postgres.public.mara
      ↓
Kafka Consumer (background thread)
      ↓
Fetch message: {"op":"c", "after":{...}, "source":{...}}
      ↓
Insert into virtual table: cdc_events_queue
      ↓
Trigger materialized view: cdc_events_consumer
      ↓
Parse & transform
      ↓
Write to: cdc_events (MergeTree)
```

**Consumer Group Management:**
- ClickHouse commits offsets to Kafka after successful processing
- If ClickHouse crashes, restarts from last committed offset
- No duplicate or lost messages (exactly-once semantics)

---

## **Phase 6: Materialized View (The Parser)** 🧠

### Real-Time Stream Processing in SQL

**View Definition:**
```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS cdc_events_consumer TO cdc_events AS
SELECT
    -- Extract timestamp from milliseconds since epoch
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
    
    -- Extract operation and cast to Enum8
    CAST(JSONExtractString(message, 'op') AS Enum8('r'=1, 'c'=2, 'u'=3, 'd'=4)) AS operation,
    
    -- Extract before/after states (full JSON)
    JSONExtractRaw(message, 'before') AS before_json,
    JSONExtractRaw(message, 'after') AS after_json,
    
    -- Extract transaction metadata
    JSONExtractString(message, 'source', 'txId') AS transaction_id,
    JSONExtractString(message, 'source', 'lsn') AS lsn,
    
    -- Store raw event for debugging
    message AS raw_event,
    
    now64(3) AS ingested_at
FROM cdc_events_queue;
```

### How Materialized Views Work

**Trigger Mechanism:**
1. New message arrives in `cdc_events_queue`
2. ClickHouse **immediately** evaluates the SELECT statement
3. Transforms the data
4. Inserts result into target table `cdc_events`
5. All happens **synchronously** - no delay!

**Example Transformation:**

**Input (from Kafka):**
```json
{
  "op": "c",
  "ts_ms": 1723122899452,
  "before": null,
  "after": {"mandt":"100","matnr":"DEMO001","mtart":"ROH",...},
  "source": {
    "db": "sourcedb",
    "schema": "public", 
    "table": "mara",
    "txId": 12345,
    "lsn": 24557016
  }
}
```

**Output (to cdc_events table):**
```
event_time:     2026-08-08 13:38:19.452
event_date:     2026-08-08
database:       sourcedb
schema:         public
table_name:     mara
primary_key:    {"mandt":"100","matnr":"DEMO001","mtart":"ROH",...}
operation:      c (Enum8 = 2)
before_json:    
after_json:     {"mandt":"100","matnr":"DEMO001","mtart":"ROH",...}
transaction_id: 12345
lsn:            24557016
raw_event:      {... full JSON ...}
ingested_at:    2026-08-08 13:38:19.687
```

### Key Parsing Logic

**1. Timestamp Conversion:**
```sql
fromUnixTimestamp64Milli(CAST(JSONExtractString(message, 'ts_ms') AS Int64))
```
- Debezium: `1723122899452` (milliseconds)
- ClickHouse: `2026-08-08 13:38:19.452` (DateTime64)

**2. Primary Key Extraction:**
```sql
JSONExtractRaw(
    COALESCE(
        JSONExtractRaw(message, 'after'),
        JSONExtractRaw(message, 'before')
    )
) AS primary_key
```
- **INSERT/UPDATE:** Use `after` (new row state)
- **DELETE:** Use `before` (deleted row state)
- Stores **entire row JSON**, not just PK fields

**3. Operation Enum:**
```sql
CAST(JSONExtractString(message, 'op') AS Enum8('r'=1, 'c'=2, 'u'=3, 'd'=4))
```
- Converts string to efficient enum (1 byte storage)
- Maps: `r`→READ, `c`→CREATE, `u`→UPDATE, `d`→DELETE

**4. Nested JSON Extraction:**
```sql
JSONExtractString(message, 'source', 'db')
```
- Navigates nested structure: `message.source.db`
- Returns: `"sourcedb"`

---

## **Phase 7: MergeTree Storage Engine**

### Permanent Storage with Optimization

**Table Definition:**
```sql
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
```

### MergeTree Features Explained

**1. Partitioning:**
```sql
PARTITION BY toYYYYMM(event_date)
```
- Creates separate folders per month: `202608`, `202609`, etc.
- Enables **fast partition drops** when TTL expires
- Query pruning: only scan relevant partitions

**Example Directory Structure:**
```
/var/lib/clickhouse/data/cdc_events/cdc_events/
├── 202608_1_1_0/          # August 2026, first part
│   ├── checksums.txt
│   ├── columns.txt
│   ├── event_time.bin
│   ├── after_json.bin
│   └── primary.idx
└── 202609_1_1_0/          # September 2026, first part
    └── ...
```

**2. Sorting (Primary Index):**
```sql
ORDER BY (event_date, table_name, primary_key, event_time)
```
- Data physically sorted on disk
- Creates **sparse primary index** every 8192 rows (granularity)
- Enables binary search for fast lookups

**Query Optimization:**
```sql
-- Fast: Uses primary index
SELECT * FROM cdc_events 
WHERE event_date = '2026-08-08' 
  AND table_name = 'mara' 
  AND primary_key LIKE '{"mandt":"100"%';

-- Slow: Full table scan
SELECT * FROM cdc_events 
WHERE transaction_id = '12345';
```

**3. TTL (Time-To-Live):**
```sql
TTL event_date + INTERVAL 90 DAY
```
- Background process runs hourly
- **Deletes entire partitions** when all rows in partition exceed TTL
- No per-row deletion overhead
- August 2026 data expires on November 6, 2026

**4. Background Merges:**
- ClickHouse periodically merges small parts into larger parts
- Reduces file count
- Improves query performance
- Applies TTL during merge

**Storage Size Estimation:**
- ~1 KB per event (with 20-column MARA table)
- 1 million events = ~1 GB
- With 90-day retention: depends on change rate

---

## **Phase 8: Query Views**

### User-Friendly Abstractions

**1. Readable View:**
```sql
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
```

**Purpose:**
- Converts Enum8 to human-readable strings
- No storage overhead (computed on-the-fly)
- **This is what you query in Tabix!**

**2. Timeline View:**
```sql
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
```

**Purpose:**
- Optimized for audit trail queries
- Shows complete history of a single record
- Orders by PK then time

**3. Stats Materialized View:**
```sql
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
```

**Purpose:**
- Pre-aggregated counts
- SummingMergeTree automatically merges during compaction
- **Much faster** than `COUNT(*)` on main table

**Query Comparison:**
```sql
-- Slow: Full table scan + aggregation
SELECT operation_type, count(*) 
FROM cdc_events_readable 
GROUP BY operation_type;

-- Fast: Pre-aggregated
SELECT operation, sum(event_count)
FROM cdc_events_stats
GROUP BY operation;
```

---

## **Phase 9: Tabix Web UI**

### Browser-Based Visualization

**Architecture:**
```
Browser (localhost:8080)
    ↓ HTTP
Tabix Pod (port 80)
    ↓ Serves static HTML/JS
Browser runs JavaScript
    ↓ HTTP API calls
ClickHouse HTTP API (localhost:8123)
    ↓ SQL Execution
ClickHouse Server (port 9000 native, 8123 HTTP)
```

**Why Two Port-Forwards?**
```powershell
# 1. Tabix UI
kubectl port-forward -n db-explorer svc/tabix 8080:80

# 2. ClickHouse API (Tabix connects from your browser, not from inside cluster)
kubectl port-forward -n db-explorer svc/clickhouse 8123:8123
```

**Connection Flow:**
1. Browser loads Tabix from `http://localhost:8080`
2. Tabix JavaScript runs in your browser
3. Browser connects to `http://127.0.0.1:8123` (ClickHouse HTTP API)
4. **Note:** Tabix never proxies queries - browser talks directly to ClickHouse!

**HTTP API Query Format:**
```http
POST http://127.0.0.1:8123/?user=default&password=clickhouse123
Content-Type: text/plain

SELECT * FROM cdc_events_readable 
WHERE JSONExtractString(after_json, 'matnr') = 'DEMO001'
ORDER BY event_time DESC
FORMAT JSON
```

**Response:**
```json
{
  "meta": [
    {"name": "event_time", "type": "DateTime64(3)"},
    {"name": "operation_type", "type": "String"},
    {"name": "before_json", "type": "String"},
    {"name": "after_json", "type": "String"}
  ],
  "data": [
    {
      "event_time": "2026-08-08 13:40:32.199",
      "operation_type": "UPDATE",
      "before_json": "{\"mandt\":\"100\",\"matnr\":\"DEMO001\",\"mtart\":\"ROH\",...}",
      "after_json": "{\"mandt\":\"100\",\"matnr\":\"DEMO001\",\"mtart\":\"FERT\",...}"
    },
    {
      "event_time": "2026-08-08 13:38:19.452",
      "operation_type": "CREATE",
      "before_json": "",
      "after_json": "{\"mandt\":\"100\",\"matnr\":\"DEMO001\",\"mtart\":\"ROH\",...}"
    }
  ],
  "rows": 2,
  "statistics": {
    "elapsed": 0.002,
    "rows_read": 2,
    "bytes_read": 1024
  }
}
```

**Tabix Features:**
- Syntax highlighting
- Query history
- Result export (CSV, JSON)
- Connection management
- Schema browser

---

## **Complete End-to-End Timeline**

### From INSERT to UI Display

**T=0ms: User executes SQL in pgAdmin**
```sql
INSERT INTO mara (mandt, matnr, mtart, ersda, ernam) 
VALUES ('100', 'DEMO001', 'ROH', '20260807', 'DEMOUSER');
```

**T=1ms: PostgreSQL WAL Write**
- Transaction writes to WAL
- Assigns LSN: `0/195B2B0`
- Assigns txId: `12345`

**T=2ms: Transaction Commits**
- WAL entry marked committed
- Data visible to readers

**T=5ms: Debezium Reads from Replication Slot**
- pgoutput plugin decodes WAL
- Converts to structured message

**T=10ms: Debezium Sends to Kafka**
- Wraps in Debezium JSON envelope
- Publishes to topic `postgres.public.mara`
- Kafka assigns offset: `42`

**T=15ms: Kafka Persists Message**
- Writes to log file
- Acknowledges to Debezium
- Message available to consumers

**T=20ms: ClickHouse Kafka Engine Polls**
- Background thread fetches batch
- Reads offset 42
- Inserts into `cdc_events_queue`

**T=21ms: Materialized View Triggers**
- Parses JSON
- Transforms fields
- Inserts into `cdc_events` (MergeTree)

**T=22ms: ClickHouse Commits Offset**
- Marks offset 42 as processed
- Prevents reprocessing

**T=30ms: Data Available for Queries**
- User runs query in Tabix
- Results include new event

**Total Latency: ~30ms** (near real-time!)

---

## **Failure Scenarios & Recovery**

### What Happens When Things Go Wrong?

**1. ClickHouse Pod Crashes**
```
Before:  Kafka offset = 42 (committed)
         cdc_events has 100 rows
Crash:   ClickHouse pod restarts
After:   Reads from Kafka starting at offset 43
         No data loss, no duplicates
```

**2. Kafka Pod Crashes**
```
Before:  Messages in memory buffer (not flushed to disk)
Crash:   Kafka pod restarts, buffer lost
Impact:  Debezium retries failed messages
Result:  No data loss (Debezium tracks LSN)
```

**3. PostgreSQL Pod Crashes**
```
Before:  Replication slot exists: debezium_mara at LSN 0/195B2B0
Crash:   PostgreSQL restarts, WAL preserved (on PVC)
After:   Debezium reconnects, continues from LSN 0/195B2B0
Result:  No data loss, no duplicates
```

**4. Debezium Pod Crashes**
```
Before:  Processing LSN 0/195B2B0, Kafka offset 42
Crash:   Debezium pod restarts
After:   Reads from replication slot (LSN preserved by PostgreSQL)
         May see duplicate messages in Kafka (Debezium is at-least-once)
Impact:  ClickHouse handles duplicates via deduplication window
```

**5. Network Partition**
```
Scenario: ClickHouse can't reach Kafka for 5 minutes
Impact:   Messages accumulate in Kafka
Recovery: When network restores, ClickHouse catches up from last offset
Result:   Temporary lag, but no data loss
```

---

## **Performance Characteristics**

### Throughput & Latency

**Typical Performance:**
- **Latency:** 10-50ms end-to-end
- **Throughput:** 10,000+ events/second per table
- **Query Speed:** <100ms for most analytics queries

**Bottlenecks:**
1. **PostgreSQL WAL generation** (CPU-bound)
2. **Kafka disk I/O** (can be SSD-optimized)
3. **ClickHouse JSON parsing** (CPU-bound)

**Optimization Tips:**
- Add Kafka partitions for parallelism
- Increase `kafka_num_consumers` in ClickHouse
- Use ClickHouse cluster (sharding)
- Tune `index_granularity` for query patterns

---

## **Key Takeaways**

1. **Zero Custom Code:** Entire pipeline is declarative (SQL + config)
2. **Near Real-Time:** Sub-second latency from database change to query
3. **Fault Tolerant:** Each component handles failures gracefully
4. **Scalable:** Can handle millions of events per day
5. **Auditable:** Complete history with before/after states
6. **Queryable:** Standard SQL for analytics

**The Beauty:** 
- No application changes required
- No triggers or audit tables in PostgreSQL
- No custom Python/Java consumers
- Pure infrastructure solution! 🎉
