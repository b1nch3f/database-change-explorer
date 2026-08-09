# Kafka Service (Redpanda)

Kafka-compatible message broker using Redpanda for CDC event streaming.

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
helm upgrade --install kafka kafka-0.1.0.tgz -n db-explorer

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=kafka -n db-explorer --timeout=120s
```

## Verify

```powershell
# Check pod status
kubectl get pods -n db-explorer -l app=kafka

# Check logs
kubectl logs -n db-explorer -l app=kafka

# List topics
kubectl exec -it -n db-explorer deployment/kafka -- rpk topic list
```

## Uninstall

```powershell
helm uninstall kafka -n db-explorer
kubectl delete pvc kafka-data -n db-explorer
```

## Configuration

- **Image**: Redpanda v24.2.4
- **Port**: 9092 (Kafka API)
- **Admin Port**: 9644
- **Advertised Listener**: kafka:9092
- **Storage**: 10Gi PVC
