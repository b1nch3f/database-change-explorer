# Backend API

FastAPI backend providing REST APIs for CDC events and ML anomaly detections from ClickHouse.

## Architecture

- **Framework**: FastAPI 0.115.0
- **Database**: ClickHouse (clickhouse-connect)
- **Data Source**: cdc_events database (CDC events, anomaly detections)
- **Container**: Python 3.12-slim
- **Port**: 8000

## API Endpoints

### Health & Info
- `GET /` - API information
- `GET /health` - Health check (verifies ClickHouse connection)

### CDC Events
- `GET /api/cdc/events` - Recent CDC events
  - Query params: `time_range` (1h, 6h, 24h, 7d, 30d), `limit`, `offset`
- `GET /api/cdc/stats` - Event statistics
  - Query params: `time_range`
- `GET /api/cdc/timeline` - Events timeline grouped by operation
  - Query params: `time_range`, `interval` (hour, day)

### Anomaly Detections
- `GET /api/anomalies` - Detected anomalies
  - Query params: `time_range`, `limit`, `offset`
- `GET /api/anomalies/stats` - Anomaly statistics
  - Query params: `time_range`
- `GET /api/anomalies/timeline` - Anomalies over time
  - Query params: `time_range`, `interval`

## Environment Variables

```bash
CLICKHOUSE_HOST=clickhouse
CLICKHOUSE_PORT=8123
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=clickhouse123
CLICKHOUSE_DATABASE=cdc_events
```

## Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Run server
uvicorn main:app --host 0.0.0.0 --port 8000 --reload

# Access API docs
http://localhost:8000/docs
```

## Docker Build

```bash
docker build -t backend-api:latest .
docker run -p 8000:8000 \
  -e CLICKHOUSE_HOST=clickhouse \
  backend-api:latest
```

## Helm Deployment

```bash
cd chart
helm package .
helm upgrade --install backend backend-0.1.0.tgz -n db-explorer

# Port forward
kubectl port-forward -n db-explorer svc/backend 8000:8000
```

## API Documentation

Interactive API documentation available at:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## CORS Configuration

CORS is enabled for all origins in development. For production, update `allow_origins` in main.py to specify your frontend domain.
