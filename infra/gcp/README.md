# GCP Infrastructure for Database Change Explorer

This directory contains Terraform configurations to provision the GCP infrastructure required for the Database Change Explorer CDC pipeline.

## Resources Created

- **GKE Autopilot Cluster** (`db-explorer`)
  - Location: asia-south1-b (Mumbai, zonal for cost efficiency)
  - Mode: Autopilot (Google-managed nodes and scaling)
  - Release channel: REGULAR
  - Logging: System components + workloads
  - Monitoring: System components + managed Prometheus

- **Artifact Registry** (`db-explorer`)
  - Location: asia-south1
  - Format: Docker
  - Purpose: Stores custom Docker images (ML inference, Backend API, CDC Consumer)

## Prerequisites

1. **Google Cloud SDK**
   ```powershell
   # Install gcloud CLI
   # https://cloud.google.com/sdk/docs/install
   
   # Authenticate
   gcloud auth login
   gcloud auth application-default login
   ```

2. **Terraform**
   ```powershell
   # Install Terraform
   # https://www.terraform.io/downloads
   
   # Verify installation
   terraform version
   ```

3. **GCP Project**
   - Create a GCP project (or use existing)
   - Enable billing for the project
   - Set the project ID in `terraform.tfvars`

## Usage

### 1. Initialize Terraform

```powershell
cd infra/gcp
terraform init
```

### 2. Review Infrastructure Plan

```powershell
terraform plan
```

This shows what resources will be created without actually creating them.

### 3. Create Infrastructure

```powershell
terraform apply
```

Review the plan and type `yes` to confirm. This will:
- Enable Container and Artifact Registry APIs
- Create GKE Autopilot cluster (~5-10 minutes)
- Create Artifact Registry repository

### 4. Configure kubectl and Docker

After infrastructure is created, configure access:

```powershell
# Configure kubectl to access the cluster
gcloud container clusters get-credentials db-explorer --region=asia-south1

# Configure Docker to push images to Artifact Registry
gcloud auth configure-docker asia-south1-docker.pkg.dev
```

Or use the commands from Terraform outputs:

```powershell
terraform output kubectl_config_command
terraform output docker_auth_command
```

### 5. Deploy Services

Once infrastructure is ready, deploy services:

```powershell
cd ../../deployment/gcp
.\build.ps1          # Build and push Docker images
.\deploy.ps1         # Deploy all services to GKE
```

## Cleanup

### Option 1: Destroy via Terraform

```powershell
cd infra/gcp
terraform destroy
```

This will delete:
- GKE cluster (all running services will be deleted)
- Artifact Registry repository (all Docker images will be deleted)

### Option 2: Manual Cleanup

```powershell
# Delete services but keep infrastructure
cd deployment/gcp
.\cleanup.ps1

# Delete cluster only
.\cleanup.ps1 -DeleteCluster

# Delete everything
.\cleanup.ps1 -DeleteCluster -DeleteRegistry
```

## Cost Estimates

**GKE Autopilot** (asia-south1):
- ~$0.10/hour for cluster management
- ~$0.05-0.10/hour for actual pod resources
- **Total: ~$0.15-0.20/hour** (~$108-144/month if running 24/7)

**Artifact Registry**:
- Storage: $0.10/GB/month
- Network egress: $0.12/GB (first 1GB free)
- **Total: ~$1-2/month** for typical usage

**Estimated Monthly Cost**: $110-150 for 24/7 operation

**Cost Optimization**:
- Delete cluster when not in use: `terraform destroy` or `cleanup.ps1 -DeleteCluster`
- For POC/demos, run only a few hours/week: ~$10-12/month

## Variables

Override defaults in `terraform.tfvars` or via `-var` flags:

| Variable | Default | Description |
|----------|---------|-------------|
| `project_id` | `database-change-explorer` | GCP Project ID |
| `region` | `asia-south1` | GCP region |
| `cluster_name` | `db-explorer` | GKE cluster name |
| `registry_name` | `db-explorer` | Artifact Registry name |

Example custom values:

```hcl
# terraform.tfvars
project_id    = "my-company-cdc"
region        = "us-central1"
cluster_name  = "cdc-cluster"
registry_name = "cdc-images"
```

## Outputs

After `terraform apply`, view outputs:

```powershell
terraform output
```

Available outputs:
- `cluster_name`: GKE cluster name
- `cluster_endpoint`: Cluster API endpoint (sensitive)
- `cluster_location`: Cluster zone
- `registry_url`: Full Artifact Registry URL
- `kubectl_config_command`: Command to configure kubectl
- `docker_auth_command`: Command to configure Docker

## Troubleshooting

**API not enabled error:**
```
Error: Error creating Cluster: googleapi: Error 403: ...API not enabled
```
Solution: Terraform should auto-enable APIs. If not, manually enable:
```powershell
gcloud services enable container.googleapis.com
gcloud services enable artifactregistry.googleapis.com
```

**Insufficient permissions:**
```
Error: Error creating Cluster: googleapi: Error 403: Forbidden
```
Solution: Ensure your account has required IAM roles:
- Kubernetes Engine Admin
- Artifact Registry Administrator
- Service Usage Admin

**Cluster creation timeout:**
```
Error: timeout while waiting for state to become 'RUNNING'
```
Solution: GKE Autopilot can take 5-10 minutes. Increase timeout or wait and retry.

## Next Steps

After infrastructure is provisioned:

1. **Build & Deploy Services**: See [../../deployment/README.md](../../deployment/README.md)
2. **Run Demo**: See [../../DEMO.md](../../DEMO.md)
3. **Monitor Costs**: https://console.cloud.google.com/billing
