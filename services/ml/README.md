# ML Anomaly Detection Service

Batch ML inference service that detects anomalies in MARA material master data using Isolation Forest.

## Overview

This service:
- Runs as a Kubernetes CronJob (every 1 minute)
- Reads new CDC events from ClickHouse (`cdc_events` table)
- Extracts material features (weight, volume, dimensions)
- Predicts anomalies using trained Isolation Forest model
- Writes results to `anomaly_detections` table
- Maintains checkpoint for incremental processing

## Architecture

```
┌──────────────┐
│  CronJob     │  Every 1 minute
│  (Scheduled) │
└──────┬───────┘
       │
       v
┌──────────────────────────────────────────────┐
│  inference.py                                │
│  1. Get last checkpoint                      │
│  2. Query new events (WHERE event_time > cp) │
│  3. Extract features from JSON               │
│  4. Pipeline.predict(features)               │
│  5. Insert into anomaly_detections           │
│  6. Update checkpoint                        │
└──────────────────────────────────────────────┘
       │
       v
┌──────────────────────────────────────────────┐
│  ClickHouse                                   │
│  - cdc_events (input)                        │
│  - anomaly_detections (output)               │
│  - ml_job_checkpoints (state)                │
└──────────────────────────────────────────────┘
```

## Model

- **Algorithm**: Isolation Forest (scikit-learn)
- **Features**: 6 numeric fields (brgew, ntgew, volum, laeng, breit, hoehe)
- **Preprocessing**: SimpleImputer (fill missing with 0)
- **Pipeline**: `anomaly_detection_pipeline.pkl`
- **Config**: `model_config.json`

## Files

```
ml/
├── Dockerfile                       # Python 3.12 + uv + scikit-learn + clickhouse-connect
├── pyproject.toml                   # Python dependencies (uv format)
├── inference.py                     # Batch inference script
├── anomaly_detection_pipeline.pkl   # Trained model (from notebooks/)
├── model_config.json                # Model metadata
├── Chart.yaml                       # Helm chart metadata
├── values.yaml                      # Configuration values
└── templates/
    └── cronjob.yaml                 # Kubernetes CronJob
```

## Build and Deploy

### 1. Build Docker Image

```powershell
cd ml
docker build -t ml-inference:latest .
cd ..
```

### 2. Deploy to Kubernetes

```powershell
cd ml/chart
helm package .
helm upgrade --install ml ml-0.1.0.tgz -n db-explorer
cd ../..
```

### 3. Verify

```powershell
# Check CronJob
kubectl get cronjobs -n db-explorer

# Check Job history
kubectl get jobs -n db-explorer

# Check logs of latest job
kubectl logs -n db-explorer job/ml-inference-<timestamp>

# Query anomaly detections
kubectl port-forward -n db-explorer svc/clickhouse 8123:8123

# In another terminal:
curl "http://localhost:8123/" --data "SELECT * FROM cdc_events.anomaly_detections ORDER BY detected_at DESC LIMIT 10 FORMAT Pretty"
```

## Configuration

Edit `values.yaml`:

```yaml
schedule: "* * * * *"  # Every 1 minute (cron syntax)
# Examples:
# "*/5 * * * *"  # Every 5 minutes
# "0 * * * *"    # Every hour
# "0 0 * * *"    # Every day at midnight
```

## Checkpoint Management

The service maintains state in `ml_job_checkpoints` table:

```sql
SELECT * FROM cdc_events.ml_job_checkpoints;
```

To reset checkpoint (reprocess all events):

```sql
DELETE FROM cdc_events.ml_job_checkpoints WHERE job_name = 'anomaly_detection';
```

## Monitoring

Check anomaly detection results:

```sql
-- Count by anomaly status
SELECT 
    is_anomaly,
    count() as count
FROM cdc_events.anomaly_detections
GROUP BY is_anomaly;

-- Recent anomalies
SELECT 
    material_id,
    anomaly_score,
    detected_at
FROM cdc_events.anomaly_detections
WHERE is_anomaly = 1
ORDER BY anomaly_score ASC
LIMIT 10;

-- Job execution stats
SELECT 
    job_name,
    last_processed_timestamp,
    processed_count,
    anomalies_detected,
    updated_at
FROM cdc_events.ml_job_checkpoints;
```

## Model Updates

To deploy a new model version:

1. Train new model in `notebooks/experiment.ipynb`
2. Copy new files:
   ```powershell
   Copy-Item notebooks\anomaly_detection_pipeline.pkl ml\
   Copy-Item notebooks\model_config.json ml\
   ```
3. Rebuild Docker image with new version tag
4. Update `values.yaml` with new tag
5. Redeploy with `helm upgrade`

## Troubleshooting

**CronJob not running:**
```powershell
kubectl describe cronjob ml-inference -n db-explorer
kubectl get events -n db-explorer --sort-by='.lastTimestamp'
```

**Job failures:**
```powershell
kubectl get jobs -n db-explorer
kubectl logs -n db-explorer job/ml-inference-<timestamp>
```

**No events processed:**
- Check if new CDC events exist in `cdc_events` table
- Verify checkpoint timestamp is not too recent
- Check ClickHouse connection (initContainer logs)

**Anomaly detection not working:**
- Verify model files are in Docker image
- Check feature extraction (JSON parsing)
- Verify features match training: `['brgew', 'ntgew', 'volum', 'laeng', 'breit', 'hoehe']`
