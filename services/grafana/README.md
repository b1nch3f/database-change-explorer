# Grafana Dashboards

**Main demo interface** - Grafana visualization service with two pre-configured dashboards for presenting CDC events and anomaly detections to stakeholders.

## What's Included

### 1. CDC Events Dashboard
**Purpose**: Monitor all database change events captured by the CDC pipeline

**Panels**:
- **Total Events Over Time**: Time-series chart showing event volume by operation type
- **Events by Operation Type**: Pie chart breakdown (CREATE, UPDATE, DELETE)
- **Event Rate**: Average events per hour metric
- **Total Events**: Count of all events in selected time range
- **Recent CDC Events**: Table with latest events including material IDs

**Demo Use Cases**:
- Present real-time database activity to stakeholders
- Show CDC event volumes and patterns
- Demonstrate change tracking capabilities
- Visualize complete audit trail

### 2. Anomaly Detections Dashboard
**Purpose**: Visualize ML-detected anomalies in material data

**Panels**:
- **Anomalies Over Time**: Time-series of detected anomalies
- **Total Anomalies**: Count with color-coded thresholds (green < 10 < yellow < 50 < red)
- **Avg Anomaly Score**: Mean isolation forest score
- **Min/Max Anomaly Score**: Score distribution
- **Detected Anomalies with Details**: Table showing material IDs, scores, and feature values (weight, volume, dimensions)

**Demo Use Cases**:
- Showcase ML anomaly detection in action
- Present data quality monitoring capabilities
- Demonstrate real-time model predictions
- Display anomaly scores and trends for stakeholders

## Features

### Time Range Selection
Both dashboards support flexible time ranges:
- Last 1 hour
- Last 6 hours
- Last 24 hours
- Last 7 days (default)
- Last 30 days

### Auto-Refresh
Dashboards automatically refresh every 30 seconds to show latest data.

### ClickHouse Integration
Direct connection to ClickHouse using the official Grafana ClickHouse datasource plugin.

## Access

```powershell
kubectl port-forward -n db-explorer svc/grafana 3000:3000
```

Open browser: **http://localhost:3000**

**Credentials**:
- Username: `admin`
- Password: `admin123`

## Configuration

### Data Source
- **Type**: grafana-clickhouse-datasource
- **Host**: clickhouse:8123
- **Database**: cdc_events
- **Protocol**: HTTP

### Dashboards Location
Dashboards are provisioned automatically from ConfigMaps and appear in the **"Database Change Explorer"** folder.

## Customization

To modify dashboards:

1. Edit the JSON in `chart/templates/configmap-dashboards.yaml`
2. Rebuild and redeploy:
   ```powershell
   cd grafana/chart
   helm package .
   helm upgrade --install grafana grafana-0.1.0.tgz -n db-explorer
   ```

Alternatively, edit dashboards in the Grafana UI (changes will persist in the pod but not survive restarts unless saved to the ConfigMap).

## Queries

### Example ClickHouse Queries Used

**Total events by operation**:
```sql
SELECT operation, count() as count 
FROM cdc_events 
WHERE event_time >= now() - INTERVAL 7 DAY 
GROUP BY operation
```

**Recent anomalies**:
```sql
SELECT detected_at, material_id, anomaly_score 
FROM anomaly_detections 
WHERE is_anomaly = 1 AND detected_at >= now() - INTERVAL 7 DAY 
ORDER BY anomaly_score ASC 
LIMIT 100
```

## Resource Usage

- **Memory**: 256Mi request, 512Mi limit
- **CPU**: 100m request, 500m limit
- **Storage**: EmptyDir (ephemeral)

## Troubleshooting

**Plugin not loading**:
```bash
# Check if ClickHouse plugin is installed
kubectl logs -n db-explorer -l app=grafana | grep clickhouse
```

**Connection errors**:
```bash
# Verify ClickHouse is accessible
kubectl exec -n db-explorer -it deployment/grafana -- curl http://clickhouse:8123
```

**Dashboard not appearing**:
```bash
# Check provisioning logs
kubectl logs -n db-explorer -l app=grafana | grep provisioning
```

## Architecture

```
Grafana Pod
  ├── grafana:11.0.0 (official image)
  ├── Plugin: grafana-clickhouse-datasource (auto-installed)
  ├── Datasource: ClickHouse (provisioned)
  └── Dashboards: CDC Events + Anomaly Detections (provisioned)
```

## Next Steps

- Add alerts for anomaly thresholds
- Create dashboard for ML job statistics
- Add drill-down links between dashboards
- Export dashboards for backup
