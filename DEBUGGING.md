# Database Change Explorer - Developer Debugging Guide

This guide provides deep technical access to all services for debugging, investigation, and advanced monitoring.

## All Services Overview

When running `kubectl get pods -n db-explorer`, you should see:
- **postgres** - PostgreSQL 16 source database
- **kafka** - Redpanda message broker
- **clickhouse** - OLAP analytics database
- **debezium** - CDC connector
- **ml-inference** - CronJob (creates job pods every minute)
- **backend** - FastAPI REST API
- **frontend** - Next.js dashboard
- **pgadmin** - PostgreSQL administration UI
- **grafana** - Monitoring dashboards
- **tabix** - ClickHouse SQL client

## All Service Credentials

| Service | URL | Username | Password | Notes |
|---------|-----|----------|----------|-------|
| **Frontend** | http://localhost:3001 | - | - | No login required |
| **Backend API** | http://localhost:8000/docs | - | - | FastAPI Swagger docs |
| **pgAdmin** | http://localhost:8081 | admin@local.com | admin123 | PostgreSQL UI |
| **Grafana** | http://localhost:3000 | admin | admin123 | Monitoring dashboards |
| **Tabix** | http://localhost:8080 | - | - | No login (configure ClickHouse connection) |

**PostgreSQL Connection** (in pgAdmin):
- Host: `postgres`, Port: `5432`, Database: `sourcedb`
- Username: `dbuser`, Password: `dbpass123`

**ClickHouse Connection** (in Tabix):
- Host: `localhost`, Port: `8123`, Database: `cdc_events`
- Username: `default`, Password: `clickhouse123`

## Developer Tools

### Backend API (REST Endpoints)

Port-forward:
```powershell
kubectl port-forward -n db-explorer svc/backend 8000:8000
```

Open: **http://localhost:8000/docs**

**Available Endpoints:**
- `GET /` - API info
- `GET /health` - Health check with database status
- `GET /api/cdc/events` - Recent CDC events (with pagination, time_range)
- `GET /api/cdc/stats` - Event statistics by operation type
- `GET /api/cdc/timeline` - Events grouped by time bucket
- `GET /api/anomalies` - Detected anomalies with feature values
- `GET /api/anomalies/stats` - Anomaly metrics (total, avg/min/max scores)
- `GET /api/anomalies/timeline` - Anomalies over time

**Example API Calls:**
```powershell
# Health check
Invoke-RestMethod -Uri http://localhost:8000/health

# CDC stats for last 24 hours
Invoke-RestMethod -Uri 'http://localhost:8000/api/cdc/stats?time_range=1d'

# Recent CDC events
Invoke-RestMethod -Uri 'http://localhost:8000/api/cdc/events?limit=10&time_range=7d'

# Anomaly statistics
Invoke-RestMethod -Uri 'http://localhost:8000/api/anomalies/stats?time_range=7d'
```

### Grafana (Developer Monitoring)

Port-forward:
```powershell
kubectl port-forward -n db-explorer svc/grafana 3000:3000
```

Open: **http://localhost:3000**
- Username: `admin`
- Password: `admin123`

**Features:**
- Time-series monitoring dashboards
- Detailed operation breakdowns
- Metric tracking over time
- ClickHouse datasource pre-configured

**Available Dashboards:**
- CDC Events Overview
- Anomaly Detection Monitoring
- System Metrics

### Tabix (SQL Investigation)

Port-forward (requires 2 terminals):
```powershell
# Terminal 1 - Tabix UI
kubectl port-forward -n db-explorer svc/tabix 8080:80

# Terminal 2 - ClickHouse HTTP
kubectl port-forward -n db-explorer svc/clickhouse 8123:8123
```

Open: **http://localhost:8080**

**Add ClickHouse Connection** (first time):
1. Click **"Add Connection"** or connection icon
2. Fill in details:
   - **Name**: `DB Explorer`
   - **Host**: `localhost` (or `127.0.0.1`)
   - **Port**: `8123`
   - **Username**: `default`
   - **Password**: `clickhouse123`
   - **Database**: `cdc_events`
3. Click **"Test"** → **"Save"**

## Advanced SQL Queries

### CDC Event Analysis

**View recent CDC events:**
```sql
SELECT * FROM cdc_events_readable 
ORDER BY event_time DESC 
LIMIT 20
```

**Event count by operation type:**
```sql
SELECT 
    operation_type,
    count(*) as total_events
FROM cdc_events_readable
GROUP BY operation_type
ORDER BY total_events DESC
```

**Events timeline (last 24 hours):**
```sql
SELECT 
    toStartOfHour(event_time) as hour,
    operation_type,
    count(*) as events
FROM cdc_events_readable
WHERE event_time >= now() - INTERVAL 1 DAY
GROUP BY hour, operation_type
ORDER BY hour DESC, events DESC
```

**Recent changes by table:**
```sql
SELECT 
    table_name,
    operation_type,
    count(*) as changes,
    max(event_time) as last_change
FROM cdc_events_readable
WHERE event_time >= now() - INTERVAL 1 HOUR
GROUP BY table_name, operation_type
ORDER BY last_change DESC
```

**Track specific material changes:**
```sql
SELECT 
    event_time,
    operation_type,
    JSONExtractString(before_json, 'mtart') AS before_mtart,
    JSONExtractString(after_json, 'mtart') AS after_mtart
FROM cdc_events_readable 
WHERE JSONExtractString(after_json, 'matnr') = 'DEMO001'
ORDER BY event_time DESC
```

**Full audit trail for a record:**
```sql
SELECT 
    event_time,
    operation_type,
    JSONExtractString(before_json, 'mtart') AS old_mtart,
    JSONExtractString(after_json, 'mtart') AS new_mtart,
    JSONExtractString(before_json, 'ernam') AS old_user,
    JSONExtractString(after_json, 'ernam') AS new_user
FROM cdc_events_readable 
WHERE JSONExtractString(after_json, 'matnr') = 'TRACK001'
ORDER BY event_time ASC
```

### Anomaly Detection Analysis

**All detected anomalies:**
```sql
SELECT 
    material_id,
    anomaly_score,
    is_anomaly,
    detected_at,
    model_version
FROM cdc_events.anomaly_detections
WHERE is_anomaly = 1
ORDER BY anomaly_score ASC
LIMIT 20
```

**Anomalies with full feature details:**
```sql
SELECT 
    a.material_id,
    a.anomaly_score,
    a.detected_at,
    JSONExtractString(e.after_json, 'brgew') AS gross_weight,
    JSONExtractString(e.after_json, 'ntgew') AS net_weight,
    JSONExtractString(e.after_json, 'volum') AS volume,
    JSONExtractString(e.after_json, 'laeng') AS length,
    JSONExtractString(e.after_json, 'breit') AS width,
    JSONExtractString(e.after_json, 'hoehe') AS height,
    e.operation_type
FROM cdc_events.anomaly_detections a
JOIN cdc_events.cdc_events_readable e ON a.primary_key = e.primary_key
WHERE a.is_anomaly = 1
ORDER BY a.anomaly_score ASC
```

**Anomaly trends over time:**
```sql
SELECT 
    toStartOfHour(detected_at) as hour,
    count(*) as anomaly_count,
    avg(anomaly_score) as avg_score
FROM cdc_events.anomaly_detections
WHERE is_anomaly = 1
GROUP BY hour
ORDER BY hour DESC
LIMIT 24
```

## ML Anomaly Detection Deep Dive

### Testing Anomaly Detection

The ML service runs every minute using an Isolation Forest model.

**Check ML CronJob status:**
```powershell
kubectl get cronjobs -n db-explorer
kubectl get jobs -n db-explorer | Select-String -Pattern 'ml-inference'
```

**View ML job logs:**
```powershell
kubectl logs -n db-explorer job/ml-inference-<job-id>
```

### Insert Test Anomalies

**Normal baseline:**
```sql
INSERT INTO mara (mandt, matnr, mtart, ersda, ernam) 
VALUES ('300', 'NORMAL01', 'ROH', '20260808', 'MLTEST');
```

**Anomaly examples:**
```sql
-- ANOMALY 1: Extremely heavy material (9999 kg)
INSERT INTO mara (mandt, matnr, mtart, ersda, ernam, brgew, ntgew, volum, laeng, breit, hoehe, gewei, meabm) 
VALUES ('300', 'ANOM001', 'ROH', '20260808', 'MLTEST', 9999.0, 9500.0, 0.100, 50, 50, 40, 'KG', 'CM');

-- ANOMALY 2: Impossible tiny dimensions (1mm³)
INSERT INTO mara (mandt, matnr, mtart, ersda, ernam, brgew, ntgew, volum, laeng, breit, hoehe, gewei, meabm) 
VALUES ('300', 'ANOM002', 'HALB', '20260808', 'MLTEST', 25.0, 22.0, 0.001, 1, 1, 1, 'KG', 'CM');

-- ANOMALY 3: Huge dimensions (9999mm)
INSERT INTO mara (mandt, matnr, mtart, ersda, ernam, brgew, ntgew, volum, laeng, breit, hoehe, gewei, meabm) 
VALUES ('300', 'ANOM003', 'FERT', '20260808', 'MLTEST', 5000.0, 4800.0, 999.0, 9999, 9999, 9999, 'KG', 'CM');
```

**Update to create anomaly:**
```sql
UPDATE mara 
SET brgew = 8888.0, ntgew = 8500.0, volum = 0.005 
WHERE matnr = 'NORMAL01';
```

Wait 1-2 minutes for next CronJob run, then check anomaly_detections table.

## System Architecture

```
PostgreSQL (Source Database)
    ↓ Logical Replication
Debezium CDC Connector
    ↓ Kafka Connect Protocol
Kafka/Redpanda (Message Broker)
    ↓ Topic: postgres.public.mara
ClickHouse Kafka Engine
    ↓ Materialized View
cdc_events Table (OLAP Storage)
    ↓ REST API
Backend (FastAPI)
    ↓ JSON HTTP
Frontend (Next.js)
    ↓ React UI
Browser Dashboard

    ↓ Parallel ML Path (every 1 minute)
ML CronJob (Python + scikit-learn)
    ↓ Isolation Forest predictions
anomaly_detections Table
    ↓ REST API
Backend endpoints
    ↓ Frontend
Anomaly Dashboard
```

## Service Dependencies

**Deployment Order:**
1. PostgreSQL (source database)
2. Kafka (message broker)
3. ClickHouse (OLAP database + init job)
4. Debezium (CDC connector + connector registration job)
5. ML (CronJob for anomaly detection)
6. Backend (FastAPI REST API)
7. Frontend (Next.js dashboard)
8. Tabix (ClickHouse SQL client)
9. pgAdmin (PostgreSQL admin UI)
10. Grafana (monitoring dashboards)

## Troubleshooting

### Check Pod Status
```powershell
kubectl get pods -n db-explorer
kubectl describe pod <pod-name> -n db-explorer
kubectl logs <pod-name> -n db-explorer
```

### Debezium Connector Status
```powershell
kubectl exec -n db-explorer deployment/debezium -- curl -s http://localhost:8083/connectors/postgres-mara-connector/status
```

### ClickHouse Database Check
```powershell
kubectl exec -n db-explorer clickhouse-0 -- clickhouse-client --password clickhouse123 --query "SHOW DATABASES"
kubectl exec -n db-explorer clickhouse-0 -- clickhouse-client --password clickhouse123 --query "SELECT count(*) FROM cdc_events.cdc_events"
```

### PostgreSQL Replication Check
```powershell
kubectl exec -n db-explorer deployment/postgres -- psql -U dbuser -d sourcedb -c "SELECT * FROM pg_replication_slots;"
```

### Backend API Health
```powershell
# Port-forward first
kubectl port-forward -n db-explorer svc/backend 8000:8000

# Then check health
Invoke-RestMethod -Uri http://localhost:8000/health
```

## Performance Tuning

### ClickHouse Query Optimization

**Check table sizes:**
```sql
SELECT 
    table,
    formatReadableSize(sum(bytes)) as size,
    sum(rows) as rows
FROM system.parts
WHERE database = 'cdc_events' AND active
GROUP BY table
ORDER BY sum(bytes) DESC
```

**Query execution statistics:**
```sql
SELECT 
    query,
    read_rows,
    read_bytes,
    memory_usage,
    formatReadableSize(memory_usage) as memory,
    query_duration_ms / 1000 as duration_sec
FROM system.query_log
WHERE type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 10
```

### Kafka/Redpanda Metrics

```powershell
kubectl exec -n db-explorer deployment/kafka -- rpk topic describe postgres.public.mara
kubectl exec -n db-explorer deployment/kafka -- rpk cluster health
```

## Cleanup

**Remove all services:**
```powershell
kubectl delete namespace db-explorer
```

**Remove specific service:**
```powershell
helm uninstall <service-name> -n db-explorer
```

**Reset everything:**
```powershell
./scripts/cleanup.ps1
```
