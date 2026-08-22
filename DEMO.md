# Database Change Explorer - Live Demo

This guide walks you through a simple stakeholder demo showing real-time change data capture.

## Prerequisites

Ensure services are deployed:
```powershell
kubectl get pods -n db-explorer
```

You need these services running:
- **backend** (FastAPI REST API)
- **postgres** (source database)

Plus locally:
- **streamlit** (visualization dashboard)
- **PostgreSQL client** (DBeaver, pgAdmin Desktop, DataGrip, or psql)

## Quick Reference

| Service | URL | Username | Password |
|---------|-----|----------|----------|
| **Streamlit** | http://localhost:8501 | - | - |
| **Backend API** | http://localhost:8000/docs | - | - |
| **PostgreSQL** | localhost:5432 | dbuser | dbpass123 |

**PostgreSQL Connection** (via port-forward):
- Host: `localhost`, Port: `5432`, Database: `sourcedb`
- Username: `dbuser`, Password: `dbpass123`
- *Use any PostgreSQL desktop client: DBeaver, pgAdmin Desktop, DataGrip, Azure Data Studio*

## Setup: Three Terminals

### Terminal 1 - Backend API

```powershell
kubectl port-forward -n db-explorer svc/backend 8000:8000
```

*Keep this running - Streamlit needs to reach the backend API.*

### Terminal 2 - PostgreSQL (Database Access)

```powershell
kubectl port-forward -n db-explorer svc/postgres 5432:5432
```

*Keep this running - Your desktop PostgreSQL client needs to reach the database.*

**Connect with your PostgreSQL client:**
- Host: `localhost`
- Port: `5432`
- Database: `sourcedb`
- Username: `dbuser`
- Password: `dbpass123`

### Terminal 3 - Streamlit Dashboard

```powershell
cd streamlit
streamlit run app.py
```

Open in browser: **http://localhost:8501**

**Features:**
- **CDC Events**: Real-time change data capture monitoring
- **Anomaly Detection**: ML-powered anomaly detection
- **Time range selector**: 1 hour
- **Auto-refresh**: 30-second intervals
- **Interactive charts**: Line charts, scatter plots, data tables

## Demo Flow

## Demo Flow

### Part 1: View Current Data

**In Streamlit Dashboard:**
1. Select **"📝 CDC Events"** from the sidebar
2. Time range is set to **"Last 1 Hour"**
3. Review stats cards: Total Events, Event Rate, Operations
4. View **"Recent Events"** table

### Part 2: Insert New Record

**In your PostgreSQL client**, run this SQL:
```sql
INSERT INTO mara (mandt, matnr, mtart, ersda, ernam) 
VALUES ('100', 'DEMO001', 'ROH', '20260807', 'DEMOUSER');
```

**In Streamlit Dashboard:**
1. Wait 5-10 seconds for CDC pipeline
2. Click 🔄 Refresh button or wait for auto-refresh
3. See **DEMO001** with **CREATE** badge (green)
4. **Total Events** counter increments

### Part 3: Update Record

**In your PostgreSQL client:**
```sql
UPDATE mara 
SET mtart = 'FERT' 
WHERE matnr = 'DEMO001';
```

**In Streamlit Dashboard:**
1. Click 🔄 Refresh button
2. Find **DEMO001** - now shows TWO rows:
   - **UPDATE** badge (blue, most recent)
   - **CREATE** badge (green, original)
3. **Operations** card shows UPDATE count increased

### Part 4: Delete Record

**In your PostgreSQL client:**
```sql
DELETE FROM mara 
WHERE matnr = 'DEMO001';
```

**In Streamlit Dashboard:**
1. Click 🔄 Refresh button
2. Find **DEMO001** - now shows THREE rows:
   - **DELETE** badge (red, newest)
   - **UPDATE** badge (blue, middle)
   - **CREATE** badge (green, original)
4. Complete audit trail preserved!

### Part 5: View Anomalies

**In your PostgreSQL client**, insert a material with unusual values:
```sql
-- Insert anomalous record: extremely heavy material with tiny dimensions
INSERT INTO mara (mandt, matnr, mtart, ersda, ernam, brgew, ntgew, volum, laeng, breit, hoehe, gewei, meabm) 
VALUES ('100', 'ANOM001', 'ROH', '20260810', 'DEMOUSER', 9999.0, 9500.0, 0.100, 50, 50, 40, 'KG', 'CM');
```

**In Streamlit Dashboard:**
1. Wait 1-2 minutes for ML CronJob to process (runs every minute)
2. Select **"⚠️ Anomaly Detection"** from the sidebar
3. Find **ANOM001** in the detected anomalies table
4. See the anomaly score indicating unusual pattern
5. Review scatter plot and time-series charts

*The ML service runs every minute detecting unusual patterns in material data.*

## Cleanup

Stop the services (Ctrl+C in each terminal):
- **Terminal 1**: Backend API (port 8000)
- **Terminal 2**: PostgreSQL (port 5432)
- **Terminal 3**: Streamlit (port 8501)

Remove all services:
```powershell
kubectl delete namespace db-explorer
```

---

**For advanced debugging, SQL queries, and developer tools**, see [DEBUGGING.md](DEBUGGING.md)

