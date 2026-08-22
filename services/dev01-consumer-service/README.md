# CDC Kafka Consumer (Java)

Enterprise-grade Java consumer service that reads Debezium CDC events from Kafka and writes to ClickHouse. Built with Spring Boot and Spring Kafka for production SAP workloads.

## Architecture

```
Kafka Topics                    Java Consumer                 ClickHouse
┌─────────────────┐            ┌──────────────────┐          ┌─────────────┐
│ postgres.public │            │                  │          │             │
│     .mara       │───────────>│  Spring Kafka    │─────────>│ cdc_events  │
│                 │            │   Consumer       │          │   table     │
└─────────────────┘            │                  │          │             │
                               │  - Batch insert  │          └─────────────┘
                               │  - Error retry   │
                               │  - Health checks │
                               └──────────────────┘
```

## Features

### 🚀 Performance
- **Batch Processing**: Configurable batch size (default: 1000 events)
- **Parallel Consumption**: 3 consumer threads per replica
- **Efficient Inserts**: JDBC batch inserts to ClickHouse
- **Horizontal Scaling**: Kafka consumer group partitioning

### 🛡️ Reliability
- **Manual Offset Commit**: Ensures at-least-once delivery
- **Error Handling**: Automatic retry on ClickHouse failures
- **Health Checks**: Kubernetes liveness/readiness probes
- **Graceful Shutdown**: 30s grace period for in-flight messages

### 📊 Observability
- **Spring Actuator**: Health, metrics, info endpoints
- **Prometheus Metrics**: Ready for Grafana dashboards
- **Structured Logging**: JSON logs with correlation IDs
- **Batch Statistics**: Total events, batches, throughput

### 🔧 Configuration
- **Environment-based**: All settings via env vars
- **Topic Pattern**: Regex subscription (e.g., `postgres\.public\..*`)
- **Consumer Group**: Configurable for multi-database support
- **Batch Tuning**: Size and timeout configurable

## Project Structure

```
dev01-consumer-service/
├── src/main/java/io/cdcconsumer/
│   ├── CdcConsumerApplication.java       # Main Spring Boot app
│   ├── config/
│   │   ├── KafkaConfig.java              # Kafka consumer config
│   │   └── ClickHouseConfig.java         # JDBC DataSource config
│   ├── model/
│   │   ├── DebeziumEnvelope.java         # Debezium event structure
│   │   ├── DebeziumSource.java           # Source metadata
│   │   └── CdcEvent.java                 # ClickHouse entity
│   ├── consumer/
│   │   └── CdcKafkaConsumer.java         # Main Kafka listener
│   └── repository/
│       └── ClickHouseRepository.java     # ClickHouse JDBC repository
├── src/main/resources/
│   └── application.yml                   # Default configuration
├── pom.xml                               # Maven dependencies
├── Dockerfile                            # Multi-stage build
└── chart/                                # Helm chart
    ├── Chart.yaml                        # Chart metadata
    ├── values.yaml                       # Configurable values
    └── templates/
        ├── deployment.yaml               # Deployment template
        └── service.yaml                  # Service template
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `KAFKA_BOOTSTRAP_SERVERS` | `kafka:9092` | Kafka broker list |
| `KAFKA_CONSUMER_GROUP` | `clickhouse-consumer` | Consumer group ID |
| `KAFKA_TOPIC_PATTERN` | `postgres\.public\..*` | Topic regex pattern |
| `KAFKA_CONSUMER_THREADS` | `3` | Parallel consumer threads |
| `CLICKHOUSE_URL` | `jdbc:clickhouse://clickhouse:8123/cdc_events` | JDBC URL |
| `CLICKHOUSE_USER` | `default` | Username |
| `CLICKHOUSE_PASSWORD` | `` | Password |
| `CLICKHOUSE_BATCH_SIZE` | `1000` | Max events per batch |
| `CLICKHOUSE_BATCH_TIMEOUT` | `5000` | Max ms to wait for batch |

### Performance Tuning

**High Throughput (100K+ events/day):**
```yaml
env:
- name: KAFKA_CONSUMER_THREADS
  value: "5"
- name: CLICKHOUSE_BATCH_SIZE
  value: "2000"
- name: CLICKHOUSE_BATCH_TIMEOUT
  value: "3000"
resources:
  limits:
    memory: "2Gi"
    cpu: "2000m"
replicas: 5
```

**Low Latency (near real-time):**
```yaml
env:
- name: CLICKHOUSE_BATCH_SIZE
  value: "100"
- name: CLICKHOUSE_BATCH_TIMEOUT
  value: "1000"
```

## Build & Deploy

### Local Build

```bash
# Build with Maven
mvn clean package -DskipTests

# Run locally
java -jar target/cdc-consumer-1.0.0.jar \
  --spring.kafka.bootstrap-servers=localhost:9092 \
  --clickhouse.url=jdbc:clickhouse://localhost:8123/cdc_events
```

### Docker Build

```bash
# Build image
docker build -t dev01-consumer-service:1.0.0 .

# Run container
docker run -d \
  --name cdc-consumer \
  -e KAFKA_BOOTSTRAP_SERVERS=kafka:9092 \
  -e CLICKHOUSE_URL=jdbc:clickhouse://clickhouse:8123/cdc_events \
  dev01-consumer-service:1.0.0
```

### Kubernetes Deployment

```bash
# Create namespace
kubectl create namespace db-explorer

# Deploy consumer with Helm
helm install dev01-consumer chart/ -n db-explorer

# Or upgrade if already installed
helm upgrade --install dev01-consumer chart/ -n db-explorer

# Check status
kubectl get pods -n db-explorer -l app=dev01-consumer-service

# View logs
kubectl logs -n db-explorer -l app=dev01-consumer-service -f

# Scale replicas
kubectl scale deployment dev01-consumer-service -n db-explorer --replicas=5
```

## Monitoring

### Health Checks

```bash
# Overall health
curl http://dev01-consumer-service:8080/actuator/health

# Response:
# {"status":"UP"}

# Detailed health
curl http://dev01-consumer-service:8080/actuator/health/liveness
curl http://dev01-consumer-service:8080/actuator/health/readiness
```

### Metrics

```bash
# Prometheus metrics
curl http://dev01-consumer-service:8080/actuator/prometheus

# Key metrics:
# - kafka_consumer_records_consumed_total
# - kafka_consumer_lag
# - clickhouse_inserts_total
# - clickhouse_insert_duration_seconds
```

### Logs

```bash
# Follow logs
kubectl logs -n db-explorer deploy/dev01-consumer-service -f

# Sample log output:
# 2026-08-21 10:15:30.123 [kafka-listener-1] INFO  CdcKafkaConsumer - Received 500 records from Kafka
# 2026-08-21 10:15:30.456 [kafka-listener-1] INFO  ClickHouseRepository - Inserted batch of 1000 events in 234ms. Total: 15000 events
```

## Testing

### Unit Tests

```bash
mvn test
```

### Integration Tests

```bash
# Requires Docker for Testcontainers
mvn verify
```

### Manual Testing

```bash
# 1. Insert test data in PostgreSQL
kubectl exec -n db-explorer postgres-0 -- \
  psql -U dbuser -d sourcedb -c "INSERT INTO mara (mandt, matnr) VALUES ('100', 'TEST001');"

# 2. Check Kafka topic
kubectl exec -n db-explorer kafka-0 -- \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic postgres.public.mara \
  --from-beginning --max-messages 1

# 3. Verify in ClickHouse
kubectl exec -n db-explorer clickhouse-0 -- \
  clickhouse-client --query="SELECT * FROM cdc_events.cdc_events ORDER BY event_time DESC LIMIT 5;"
```

## Troubleshooting

### Consumer Not Starting

```bash
# Check logs
kubectl logs -n db-explorer deploy/dev01-consumer-service

# Common issues:
# - Kafka not reachable: Check KAFKA_BOOTSTRAP_SERVERS
# - ClickHouse not ready: Check CLICKHOUSE_URL
# - Invalid topic pattern: Check KAFKA_TOPIC_PATTERN regex
```

### No Events Consumed

```bash
# Check consumer group status
kubectl exec -n db-explorer kafka-0 -- \
  /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group clickhouse-consumer \
  --describe

# Check if topics exist
kubectl exec -n db-explorer kafka-0 -- \
  /opt/kafka/bin/kafka-topics.sh \
  --list --bootstrap-server localhost:9092 | grep postgres

# Check topic pattern matching
# Pattern: postgres\.public\..*
# Should match: postgres.public.mara, postgres.public.vbak
```

### High Consumer Lag

```bash
# Check lag
kubectl exec -n db-explorer kafka-0 -- \
  /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group clickhouse-consumer \
  --describe

# Solutions:
# 1. Scale up replicas
kubectl scale deployment dev01-consumer-service -n db-explorer --replicas=5

# 2. Increase batch size
kubectl set env deployment/dev01-consumer-service -n db-explorer \
  CLICKHOUSE_BATCH_SIZE=2000

# 3. Add more consumer threads
kubectl set env deployment/dev01-consumer-service -n db-explorer \
  KAFKA_CONSUMER_THREADS=5
```

### ClickHouse Insert Failures

```bash
# Check ClickHouse logs
kubectl logs -n db-explorer clickhouse-0

# Check table exists
kubectl exec -n db-explorer clickhouse-0 -- \
  clickhouse-client --query="SHOW TABLES FROM cdc_events;"

# Test connection
kubectl exec -n db-explorer deploy/dev01-consumer-service -- \
  wget -O- http://clickhouse:8123/ping
```

## Migration from Kafka Engine

### Before (ClickHouse Kafka Engine)

```sql
-- OLD: Kafka engine table + materialized view
CREATE TABLE cdc_events_queue (...) ENGINE = Kafka;
CREATE MATERIALIZED VIEW cdc_events_consumer TO cdc_events AS SELECT ...;
```

**Limitations:**
- ❌ No horizontal scaling (single ClickHouse instance)
- ❌ Limited error handling (silent failures)
- ❌ No metrics/observability
- ❌ Tight coupling (ClickHouse restarts = data loss)

### After (Decoupled Java Consumer)

```java
// NEW: Standalone Spring Kafka consumer
@KafkaListener(topicPattern = "postgres\\.public\\..*")
public void consume(List<ConsumerRecord<String, String>> records) {
    // Parse, batch, insert
}
```

**Benefits:**
- ✅ Horizontal scaling (5+ replicas)
- ✅ Robust error handling (retries, dead letter queue)
- ✅ Full observability (Prometheus, logs, traces)
- ✅ Loose coupling (independent lifecycle)

### Migration Steps
helm install dev01-consumer chart/ -n db-explorer
1. **Deploy Java Consumer:**
   ```bash
   kubectl apply -f chart/deployment.yaml
   ```

2. **Update ClickHouse (remove Kafka engine):**
   ```bash
   # Already updated in init.sql - Kafka engine removed
   kubectl rollout restart statefulset/clickhouse -n db-explorer
   ```

3. **Verify Both Consumers Running:**
   ```bash
   # Check consumer group has 2 members (old + new)
   kubectl exec -n db-explorer kafka-0 -- \
     /opt/kafka/bin/kafka-consumer-groups.sh \
     --bootstrap-server localhost:9092 \
     --group clickhouse-consumer \
     --describe
   ```

4. **Monitor for Duplicates:**
   ```sql
   -- Should see ~2x events temporarily (both consumers writing)
   SELECT count() FROM cdc_events.cdc_events WHERE event_time > now() - INTERVAL 5 MINUTE;
   ```

5. **Stop Old Consumer (Kafka Engine):**
   ```bash
   # Delete Kafka engine table (stops consumer)
   kubectl exec -n db-explorer clickhouse-0 -- \
     clickhouse-client --query="DROP TABLE IF EXISTS cdc_events.cdc_events_queue;"
   ```

6. **Cleanup:**
   ```sql
   -- Remove materialized view (if exists)
   DROP VIEW IF EXISTS cdc_events.cdc_events_consumer;
   ```

## Production Readiness Checklist

- [x] **Containerized**: Multi-stage Docker build
- [x] **Health Checks**: Liveness/readiness probes
- [x] **Resource Limits**: Memory and CPU defined
- [x] **Graceful Shutdown**: 30s termination grace period
- [x] **Metrics**: Prometheus-ready actuator endpoints
- [x] **Logging**: Structured JSON logs
- [x] **Configuration**: Externalized via env vars
- [x] **Security**: Non-root user in container
- [x] **Scaling**: Horizontal via replica count
- [x] **Testing**: Unit and integration tests

## Next Steps

1. **Add More Tables**: Update `table.include.list` in Debezium connector
2. **Add New Database**: Deploy separate consumer with different topic pattern
3. **Monitor Performance**: Set up Grafana dashboards with Prometheus metrics
4. **Tune Batching**: Adjust batch size and timeout based on load
5. **Add Alerts**: Configure alerts for consumer lag, errors, downtime

## License

MIT License - Open source generic CDC consumer solution.
