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
Invoke-RestMethod -Uri http://localhost:8083/connectors/postgres-mara-connector/status  # or your connector.name
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
- **Plugin**: pgoutput

The connector is configured from `values.yaml` (`connector:`), rendered into the `debezium-connector-config` ConfigMap, and applied by a post-install/post-upgrade Job with `PUT /connectors/{name}/config`. Changing a value and running `helm upgrade` updates the running connector.

| Value | Default | Purpose |
| --- | --- | --- |
| `connector.name` | `postgres-mara-connector` | Connector name in Kafka Connect |
| `connector.database` | `sourcedb` | Database to capture |
| `connector.topicPrefix` | `dev01` | Topics are `<prefix>.<schema>.<table>` |
| `connector.slotName` | `debezium_dev01` | Replication slot; one per connector |
| `connector.tableIncludeList` | `[public.mara]` | Tables to capture |
| `connector.messageKeyColumns` | `""` (primary key) | Kafka key per table, e.g. `public.messages:conversation_id` so all changes for one conversation land on one partition, in order |
| `connector.replicaIdentity` | `[public.mara:FULL]` | Replica identity Debezium sets at start, so updates and deletes carry the full old row |
| `connector.tombstonesOnDelete` | `true` | Emit a tombstone after each delete, for compacted topics and erasure |
| `connector.snapshotMode` | `initial` | Snapshot existing rows on first start |
| `connector.extraConfig` | `{}` | Any other Debezium property, passed through |
| `credentials.existingSecret` | `postgres-credentials` | Secret with `username` and `password` keys |

### Credentials

The database user and password are never in the connector config. The Secret named by `credentials.existingSecret` is mounted at `/etc/debezium/secrets/postgres`, and the config refers to it with `${dir:/etc/debezium/secrets/postgres:password}`, resolved by Kafka Connect's `DirectoryConfigProvider` at runtime. The Connect REST API shows only the placeholder.

The postgres chart creates `postgres-credentials` from its demo values. For real deployments, create the Secret yourself (or sync it from a vault) and set `credentials.existingSecret` on both charts.

### Example: capturing another application's tables

```yaml
connector:
  name: agent-platform-cdc
  database: platform
  topicPrefix: platform
  slotName: debezium_platform
  tableIncludeList: [public.messages]
  messageKeyColumns: "public.messages:conversation_id"
  replicaIdentity: ["public.messages:FULL"]
credentials:
  existingSecret: platform-db-cdc
```

### Replication slot safety

A slot keeps WAL on the database until the connector confirms it. If the connector stops, WAL grows until the disk fills. Two guards:

- Postgres runs with `max_slot_wal_keep_size` (postgres chart `config.maxSlotWalKeepSize`, default 2GB). Past it, the slot is invalidated instead of the disk filling; the connector then needs a new snapshot.
- Grafana has a **CDC Replication Slots** dashboard and an alert when a slot retains more than `alerts.slotRetainedBytes` (default 1 GiB) for 5 minutes.
