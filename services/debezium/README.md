# Debezium Service

Kafka Connect with Debezium PostgreSQL connector for CDC capture.

## Prerequisites

- Rancher Desktop with Kubernetes enabled
- Helm 3 installed
- kubectl configured
- **postgres** and **kafka** services must be deployed first

## Deploy

```powershell
# Package the Helm chart
cd chart
helm package .

# Install to Kubernetes (namespace must exist)
helm upgrade --install debezium debezium-0.1.0.tgz -n db-explorer

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=debezium -n db-explorer --timeout=120s
```

**Note**: The PostgreSQL connector is automatically registered via a Kubernetes Job after deployment.

## Verify

```powershell
# Check Debezium pod status
kubectl get pods -n db-explorer -l app=debezium

# Check connector registration job
kubectl get jobs -n db-explorer -l app=debezium
kubectl logs -n db-explorer job/debezium-register-connector

# Check Debezium logs
kubectl logs -n db-explorer -l app=debezium

# Verify connector is running
kubectl port-forward -n db-explorer svc/debezium 8083:8083
# In another terminal:
Invoke-RestMethod -Uri http://localhost:8083/connectors/postgres-mara-connector/status
```

## Uninstall

```powershell
# Uninstall Helm release (this removes the connector automatically)
helm uninstall debezium -n db-explorer
```

## Configuration

- **Image**: debezium/connect:2.7.0.Final
- **Port**: 8083 (REST API)
- **Bootstrap Servers**: kafka:9092
- **Connector Config**: postgres-connector.json
- **Tables**: public.mara
- **Plugin**: pgoutput
