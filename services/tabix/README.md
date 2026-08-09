# Tabix Service

Web UI for ClickHouse query and visualization.

## Prerequisites

- Rancher Desktop with Kubernetes enabled
- Helm 3 installed
- kubectl configured
- **clickhouse** service must be deployed first

## Deploy

```powershell
# Package the Helm chart
cd chart
helm package .

# Install to Kubernetes (namespace must exist)
helm upgrade --install tabix tabix-0.1.0.tgz -n db-explorer

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=tabix -n db-explorer --timeout=120s
```

## Access UI

```powershell
# Port-forward to access locally
kubectl port-forward -n db-explorer svc/tabix 8080:80

# Open browser to http://localhost:8080
```

## Connect to ClickHouse

In the Tabix UI:
- **Host**: clickhouse
- **Port**: 9000
- **User**: default
- **Password**: clickhouse123
- **Database**: cdc_events

## Query CDC Events

```sql
-- Count total events
SELECT count(*) FROM cdc_events;

-- Recent events
SELECT * FROM cdc_events ORDER BY timestamp DESC LIMIT 10;

-- Events by operation type
SELECT operation, count(*) FROM cdc_events GROUP BY operation;

-- Use the readable view
SELECT * FROM cdc_events_readable LIMIT 10;

-- Timeline of changes
SELECT * FROM cdc_timeline ORDER BY event_hour DESC LIMIT 24;
```

## Uninstall

```powershell
helm uninstall tabix -n db-explorer
```

## Configuration

- **Image**: spoonest/clickhouse-tabix-web-client:latest
- **Port**: 80 (HTTP)
- **Service**: ClusterIP
- **Access**: Via port-forward or Ingress
