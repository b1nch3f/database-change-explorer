# PostgreSQL Service

Source database with logical replication enabled for CDC.

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
helm upgrade --install postgres postgres-0.1.0.tgz -n db-explorer

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=postgres -n db-explorer --timeout=120s
```

## Verify

```powershell
# Check pod status
kubectl get pods -n db-explorer -l app=postgres

# Check logs
kubectl logs -n db-explorer -l app=postgres

# Test connection
kubectl exec -it -n db-explorer deployment/postgres -- psql -U dbuser -d sourcedb -c "\dt"
```

## Uninstall

```powershell
helm uninstall postgres -n db-explorer
kubectl delete pvc postgres-data -n db-explorer
```

## Configuration

- **User**: dbuser
- **Password**: dbpass123
- **Database**: sourcedb
- **Port**: 5432
- **WAL Level**: logical (for CDC)
- **Init Script**: Creates MARA table with sample data
