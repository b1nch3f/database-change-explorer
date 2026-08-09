# Database Change Explorer

CDC-based analytics platform that captures PostgreSQL changes and stores them in ClickHouse.

## Quick Start (Automated)

Deploy the entire stack with automation scripts:

```powershell
# 1. Build all Helm charts
.\scripts\build.ps1

# 2. Deploy everything
.\scripts\deploy.ps1

# 3. Clean up everything
.\scripts\cleanup.ps1
```

**For live demo:** See [DEMO.md](DEMO.md) for step-by-step instructions with pgAdmin and Tabix UIs.

## Manual Setup

Create the namespace first:

```powershell
kubectl create namespace db-explorer
```

## Deployment Order

Deploy services in this order (dependencies first):

1. **[postgres](postgres/README.md)** - Source database with logical replication
2. **[kafka](kafka/README.md)** - Message broker (Redpanda)
3. **[clickhouse](clickhouse/README.md)** - Analytics database with native Kafka consumption
4. **[debezium](debezium/README.md)** - CDC connector (requires postgres + kafka)
5. **[ml](ml/README.md)** - ML anomaly detection batch service (CronJob, every 1 minute)
6. **[streamlit](streamlit/README.md)** - Stakeholder demo dashboard (interactive, no SQL required)
7. **[pgadmin](pgadmin/README.md)** - PostgreSQL UI for data manipulation
8. **[grafana](grafana/README.md)** - Developer monitoring dashboards
9. **[tabix](tabix/README.md)** - ClickHouse SQL interface for investigation

**Note**: ClickHouse consumes CDC events directly from Kafka using its native Kafka engine. No separate consumer service is needed. ML service reads from ClickHouse and writes anomaly detections back.

## Manual Deployment Commands

If you prefer to deploy manually instead of using `deploy.ps1`:

```powershell
# 0. Create namespace
kubectl create namespace db-explorer

# 1. PostgreSQL
cd postgres/chart
helm package . && helm upgrade --install postgres postgres-0.1.0.tgz -n db-explorer
cd ../..

# 2. Kafka
cd kafka/chart
helm package . && helm upgrade --install kafka kafka-0.1.0.tgz -n db-explorer
cd ../..

# 3. ClickHouse
cd clickhouse/chart
helm package . && helm upgrade --install clickhouse clickhouse-0.1.0.tgz -n db-explorer
cd ../..

# 4. Debezium (connector auto-registers via Job)
cd debezium/chart
helm package . && helm upgrade --install debezium debezium-0.1.0.tgz -n db-explorer
cd ../..

# 5. ML (build Docker image first, then deploy)
cd ml
docker build -t ml-inference:latest .
cd chart
helm package . && helm upgrade --install ml ml-0.1.0.tgz -n db-explorer
cd ../..

# 6. Streamlit (stakeholder demo dashboard)
cd streamlit
docker build -t streamlit-dashboard:latest .
cd chart
helm package . && helm upgrade --install streamlit streamlit-0.1.0.tgz -n db-explorer
cd ../..

# 7. pgAdmin (PostgreSQL UI for data manipulation)
cd pgadmin/chart
helm package . && helm upgrade --install pgadmin pgadmin-0.1.0.tgz -n db-explorer
cd ../..

# 8. Grafana (developer monitoring dashboards)
cd grafana/chart
helm package . && helm upgrade --install grafana grafana-0.1.0.tgz -n db-explorer
cd ../..

# 9. Tabix (ClickHouse SQL interface for investigation)
cd tabix/chart
helm package . && helm upgrade --install tabix tabix-0.1.0.tgz -n db-explorer
cd ../..
```

## Verify

```powershell
kubectl get pods -n db-explorer
kubectl get svc -n db-explorer
```

## Cleanup

```powershell
# Automated cleanup (removes entire namespace)
.\scripts\cleanup.ps1

# Or manual cleanup
kubectl delete namespace db-explorer
```

## Documentation

- **[DEMO.md](DEMO.md)** - Live demo guide with pgAdmin and Tabix UIs
- **[deep-dive.md](deep-dive.md)** - Technical deep-dive into CDC pipeline internals

Each service has its own README with detailed instructions:
- [postgres/README.md](postgres/README.md)
- [kafka/README.md](kafka/README.md)
- [clickhouse/README.md](clickhouse/README.md) - includes native Kafka integration
- [debezium/README.md](debezium/README.md)
- [ml/README.md](ml/README.md) - ML anomaly detection batch service
- [streamlit/README.md](streamlit/README.md) - Stakeholder demo dashboard
- [pgadmin/README.md](pgadmin/README.md) - PostgreSQL data manipulation UI
- [grafana/README.md](grafana/README.md) - Developer monitoring dashboards
- [tabix/README.md](tabix/README.md) - ClickHouse SQL investigation tool
