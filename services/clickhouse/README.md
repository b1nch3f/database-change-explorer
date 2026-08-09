# ClickHouse Service

Analytical database for storing and querying CDC events. Uses native Kafka engine to consume events directly from Kafka - no separate consumer service needed!

## Prerequisites

- Rancher Desktop with Kubernetes enabled
- Helm 3 installed
- kubectl configured

## Deploy

```powershell
# Package the Helm chart
cd chart
helm package .

# Install to Kubernetes (namespace must exist)
helm upgrade --install clickhouse clickhouse-0.1.0.tgz -n db-explorer

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=clickhouse -n db-explorer --timeout=120s
```

## Verify

```powershell
# Check pod status
kubectl get pods -n db-explorer -l app=clickhouse

# Check logs
kubectl logs -n db-explorer clickhouse-0

# Test connection
kubectl exec -it -n db-explorer clickhouse-0 -- clickhouse-client --user default --password clickhouse123 --query "SHOW DATABASES"

# Check cdc_events table
kubectl exec -it -n db-explorer clickhouse-0 -- clickhouse-client --user default --password clickhouse123 --query "SELECT count(*) FROM cdc_events.cdc_events"
```

## Uninstall

```powershell
helm uninstall clickhouse -n db-explorer
kubectl delete pvc clickhouse-data-clickhouse-0 -n db-explorer
```

## Configuration

- **User**: default
- **Password**: clickhouse123
- **HTTP Port**: 8123
- **Native Port**: 9000
- **Database**: cdc_events
- **Table**: cdc_events (MergeTree, 90-day TTL)
- **Storage**: 10Gi PVC per replica

## Kafka Integration

ClickHouse uses its native Kafka engine to consume CDC events:

- **Kafka Table**: `cdc_events_queue` - consumes from `postgres.public.mara` topic
- **Materialized View**: `cdc_events_consumer` - parses Debezium envelope and writes to `cdc_events`
- **Consumer Group**: `clickhouse-consumer`

To check Kafka consumption status:

```powershell
# Check if Kafka table is consuming
kubectl exec -it -n db-explorer clickhouse-0 -- clickhouse-client --user default --password clickhouse123 --query "SELECT * FROM system.kafka_consumers"

# View recent events
kubectl exec -it -n db-explorer clickhouse-0 -- clickhouse-client --user default --password clickhouse123 --query "SELECT * FROM cdc_events.cdc_events_readable ORDER BY event_time DESC LIMIT 10"
```
