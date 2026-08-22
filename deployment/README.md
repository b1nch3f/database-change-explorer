# Deployment Directory

This directory contains deployment scripts for different environments.

**For infrastructure provisioning**, see [../infra/gcp/README.md](../infra/gcp/README.md) (Terraform for GCP)

## Structure

```
deployment/
├── local/          # For local Kubernetes (Minikube, Kind, Docker Desktop)
│   ├── build.ps1   # Build images locally, package Helm charts
│   ├── deploy.ps1  # Deploy to local Kubernetes
│   └── cleanup.ps1 # Remove all services from local cluster
│
└── gcp/            # For Google Cloud Platform (GKE Autopilot)
    ├── build.ps1   # Build and push images to Artifact Registry
    ├── deploy.ps1  # Deploy to GKE cluster
    └── cleanup.ps1 # Remove services from GKE (optional: delete cluster)
```

## Local Development

### Prerequisites
- Docker Desktop with Kubernetes enabled OR Minikube OR Kind
- kubectl
- helm
- Maven 3.9+ (for Java consumer) - **NOT required** (Docker multi-stage build handles it)
- Python 3.11+ (for ML/Backend) - **NOT required** (Docker handles it)

### Usage

```powershell
# Build everything
.\deployment\local\build.ps1

# Deploy all services
.\deployment\local\deploy.ps1

# Cleanup
.\deployment\local\cleanup.ps1
```

## GCP Deployment

### Prerequisites

**Infrastructure** (one-time setup):
- Google Cloud account with billing enabled
- gcloud CLI installed and authenticated
- Terraform (for infrastructure provisioning)

See [../infra/gcp/README.md](../infra/gcp/README.md) for infrastructure setup.

**Deployment**:
- GKE cluster running (created via Terraform or manually)
- kubectl configured for GKE
- helm
- Docker

### First-time Setup

**Option 1: Terraform (Recommended)**

See [../infra/gcp/README.md](../infra/gcp/README.md) for complete Terraform setup.

```powershell
# Navigate to infra directory
cd infra/gcp

# Initialize and apply
terraform init
terraform apply

# Configure kubectl and Docker (use output commands)
terraform output kubectl_config_command
terraform output docker_auth_command
```

**Option 2: Manual gcloud commands**

```powershell
# 1. Authenticate
gcloud auth login --update-adc

# 2. Set project
gcloud config set project YOUR_PROJECT_ID

# 3. Enable APIs
gcloud services enable container.googleapis.com artifactregistry.googleapis.com

# 4. Create GKE Autopilot cluster
gcloud container clusters create-auto db-explorer --region=asia-south1

# 5. Get credentials
gcloud container clusters get-credentials db-explorer --region=asia-south1
```

### Usage

```powershell
# Build and push images to Artifact Registry
.\deployment\gcp\build.ps1

# Deploy all services to GKE
.\deployment\gcp\deploy.ps1

# Cleanup (delete namespace only)
.\deployment\gcp\cleanup.ps1

# Cleanup and delete entire cluster
.\deployment\gcp\cleanup.ps1 -DeleteCluster

# Cleanup, delete cluster AND registry images
.\deployment\gcp\cleanup.ps1 -DeleteCluster -DeleteRegistry
```

### Custom Parameters

Both build and deploy scripts accept parameters:

```powershell
# Use different project/region/repo
.\deployment\gcp\build.ps1 -ProjectId "my-project" -Region "us-central1" -RepoName "my-repo"
.\deployment\gcp\deploy.ps1 -ProjectId "my-project" -Region "us-central1" -RepoName "my-repo"
```

## Cost Management

### Local
- **Cost:** Free (uses local resources)
- **Resources:** ~4-6 GB RAM, 4 CPU cores recommended

### GCP (Autopilot)
- **Running:** ~$0.20-0.30/hour
- **Idle:** ~$0.01/hour (minimal control plane)
- **Demo (4 hours):** ~$0.80-1.20
- **Development (40 hours/month):** ~$10-12

**To minimize costs:**
1. Delete the cluster after demos: `.\scripts\gcp\cleanup.ps1 -DeleteCluster`
2. Recreate when needed (5-10 minutes)
3. Use local development for most coding work

## Key Differences

| Aspect | Local | GCP |
|--------|-------|-----|
| **Image Storage** | Local Docker daemon | Artifact Registry |
| **Image Pull** | `imagePullPolicy: Never` | `imagePullPolicy: IfNotPresent` |
| **Scaling** | Limited by machine | Autopilot auto-scales |
| **Cost** | Free | ~$0.20-0.30/hour |
| **Internet Access** | Required for helm packages | Full internet |
| **Best For** | Development, testing | Demos, POCs, production-like |

## Troubleshooting

### Local Issues

**Pods stuck in ImagePullBackOff:**
- Ensure images are built: `.\deployment\local\build.ps1`
- Check image names match deployment specs

**Out of resources:**
- Increase Docker Desktop resources (Settings → Resources)
- OR reduce replica counts in Helm values.yaml files

### GCP Issues

**Authentication errors:**
```powershell
gcloud auth login --update-adc
gcloud auth configure-docker asia-south1-docker.pkg.dev
```

**Image push fails:**
- Ensure Artifact Registry repository exists
- Re-run build script (creates repo automatically)

**Deployment fails:**
- Verify kubectl context: `kubectl config current-context`
- Get credentials again: `gcloud container clusters get-credentials db-explorer --region=asia-south1`

**High costs:**
- Delete cluster when not in use: `.\deployment\gcp\cleanup.ps1 -DeleteCluster`
- Or use Terraform: `cd infra/gcp && terraform destroy`
- Monitor usage: https://console.cloud.google.com/billing

## Next Steps

After deployment, see:
- [DEMO.md](../DEMO.md) - Live demo walkthrough
- [DEBUGGING.md](../DEBUGGING.md) - Advanced debugging and SQL queries
- [services/dev01-consumer-service/README.md](../services/dev01-consumer-service/README.md) - Consumer documentation
