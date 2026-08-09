# Technical Design Document (TDD)

## Database Change Explorer

**Version:** 0.3

**Status:** Draft

---

# 1. Objective

Database Change Explorer is a Change Data Capture (CDC) analytics platform that consumes Debezium-compatible events and enables exploration of database changes.

The platform is responsible for:

* Ingesting CDC events
* Persisting immutable event history
* Providing SQL-based change analysis
* Building higher-level change intelligence capabilities

The platform does **not** perform Change Data Capture itself.

---

# 2. Scope

## In Scope

* Debezium-compatible CDC ingestion
* Multi-database support
* Initial database snapshot
* Continuous CDC ingestion
* Immutable event storage
* SQL-based exploration
* Event timeline analysis
* Window-based delta analysis
* 90-day hot event retention

## Out of Scope

* Historical WAL replay
* CDC backfill prior to onboarding
* Long-term archival
* Archive retrieval
* REST APIs
* Web UI
* Authentication & RBAC
* Monitoring dashboards
* Alerting

---

# 3. System Boundary

The platform begins consuming CDC events from Kafka.

Database connectivity and CDC configuration are external administrative responsibilities.

```text
                External Environment

 Database
     │
     ▼
 Debezium
     │
 Kafka Connect
     │
═══════════════════════════════════════

             Platform Boundary

 Kafka / Redpanda
      │
      ▼
 CDC Event Consumer
      │
      ▼
 ClickHouse (cdc_events)
      │
      ▼
 SQL Client
```

---

# 4. Administrator Activities

## Configure Source Database

Supported databases:

* PostgreSQL
* MySQL
* SQL Server
* Oracle

Additional database vendors can be supported provided they produce Debezium-compatible events.

---

## Configure Debezium

Debezium must be configured to perform:

* Initial Snapshot
* Continuous CDC

```text
                    Debezium

             ┌────────┴────────┐
             ▼                 ▼
     Initial Snapshot     WAL Streaming
          (op = r)         (c / u / d)
             │                 │
             └────────┬────────┘
                      ▼
                   Kafka
```

### Initial Snapshot

Produces one **READ** event (`op = r`) for every existing row in every monitored table.

**Purpose**

* Establish the initial observed database state.
* Provide a baseline for future analysis.

Snapshot events are **not** interpreted as INSERT operations.

### Continuous CDC

After snapshot completion, Debezium continuously streams:

* Create (`op = c`)
* Update (`op = u`)
* Delete (`op = d`)

These represent actual database mutations.

---

## Configure Kafka

Debezium publishes events to Kafka topics.

Example:

```text
customer
order
invoice
product
```

---

## Verify Ingestion

Verify that events are successfully arriving in Kafka and being persisted into ClickHouse.

---

# 5. Platform Components

```text
Kafka / Redpanda
        │
        ▼
CDC Event Consumer
        │
        ▼
ClickHouse (cdc_events)
```

## CDC Event Consumer

### Responsibilities

* Consume Kafka topics
* Validate Debezium events
* Preserve event ordering
* Persist immutable events

The consumer performs no business transformations.

---

## ClickHouse

Acts as the immutable event store.

### Responsibilities

* Store every CDC event exactly once
* Support SQL-based exploration
* Retain hot event history for 90 days

Events are never updated or modified.

---

# 6. Event Model

The platform stores two categories of events.

## Snapshot Events

Operation:

```text
op = r
```

Meaning:

> This row existed when CDC onboarding began.

### Purpose

* Establish baseline state
* Initialize row history

Snapshot events are **not** interpreted as row creation events.

---

## Change Events

Operations:

```text
op = c
op = u
op = d
```

Meaning:

* Create
* Update
* Delete

These represent actual database mutations after CDC begins.

---

# 7. Event Store

Table:

```text
cdc_events
```

| Column         | Description                  |
| -------------- | ---------------------------- |
| event_time     | Event timestamp              |
| database       | Source database              |
| schema         | Source schema                |
| table_name     | Source table                 |
| primary_key    | Record identifier            |
| operation      | r / c / u / d                |
| before_json    | Previous row image           |
| after_json     | Current row image            |
| transaction_id | Transaction identifier       |
| lsn            | Database Log Sequence Number |
| raw_event      | Complete Debezium payload    |

The original Debezium payload is preserved without modification.

---

# 8. User Activities

The initial implementation is SQL-only.

No REST API or UI is included.

## Activity 1 — Event Explorer

**Question**

> Show every CDC event.

Expected output:

* Snapshot events
* Create events
* Update events
* Delete events

ordered chronologically.

---

## Activity 2 — Timeline

**Question**

> Show every event associated with a specific record.

Example:

```text
r
u
u
d
```

---

## Activity 3 — Window Delta

**Question**

> What mutations occurred between two timestamps?

### Processing

1. Retrieve all events inside the selected window.
2. Group events by `(table_name, primary_key)`.
3. Collapse multiple events into a summarized mutation.
4. Produce field-level differences.

Examples:

```text
UPDATE
UPDATE
UPDATE

↓

UPDATE
```

```text
INSERT
UPDATE

↓

INSERT
```

```text
UPDATE
DELETE

↓

DELETE
```

```text
INSERT
UPDATE
DELETE

↓

Transient Lifecycle
```

The SQL implementation will be refined during experimentation.

---

# 9. Historical WAL Replay

## Current Scope

The platform guarantees complete event history beginning with CDC onboarding.

Onboarding consists of:

* Initial Snapshot (`op = r`)
* Continuous CDC (`op = c`, `u`, `d`)

---

## Out of Scope

The current implementation does not support:

* Historical WAL replay
* Logical decoding of archived WAL
* CDC reconstruction prior to onboarding
* Historical event backfill

Consequently, mutations that occurred before CDC onboarding cannot be reconstructed.

---

## Future Requirements

Supporting historical replay would require:

* WAL archiving enabled
* Long-term WAL retention
* Historical logical decoding
* Backfill pipeline
* Event ordering reconciliation
* Idempotent ingestion

This functionality is intentionally deferred.

---

# 10. Data Retention

## Hot Storage

**Storage**

* ClickHouse

**Retention**

* **90 days**

### Purpose

* Event Explorer
* Timeline
* Window Delta
* SQL analysis

Events older than 90 days are automatically removed.

---

# 11. Long-Term Archival

## Current Scope

Long-term archival is **out of scope** for the current implementation.

No archival storage is maintained after events expire from ClickHouse.

---

## Future Direction

A future version may introduce an archival tier.

Possible architecture:

```text
ClickHouse (90 Days)

        │

        ▼

Object Storage
(S3 / Azure Blob / GCS / MinIO)

        │

Parquet Files
```

Potential capabilities:

* Configurable archive retention
* Archive search
* Historical replay
* Restore archived data
* Cost-optimized long-term storage

This capability is intentionally deferred until the core event model has been validated.

---

# 12. Success Criteria

The implementation is considered successful when:

* Snapshot events are successfully ingested.
* CDC events are successfully ingested.
* Events are stored without loss.
* SQL queries can explore the event log.
* SQL queries can retrieve row timelines.
* SQL queries can produce window-based delta summaries.

---

# 13. Future Enhancements

After validating the event model using SQL:

* REST API
* React Web UI
* Event Explorer
* Timeline Explorer
* Window Delta Explorer
* Search and filtering
* Saved queries
* Authentication & RBAC
* Monitoring
* Dashboards
* Alerting
* Multi-tenant support
