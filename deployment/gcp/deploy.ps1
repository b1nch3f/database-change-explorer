#!/usr/bin/env pwsh
# deploy.ps1 - Deploy all Database Change Explorer services to GKE

param(
    [string]$ProjectId = "database-change-explorer",
    [string]$Region = "asia-south1",
    [string]$RepoName = "db-explorer",
    [switch]$SkipNamespace
)

Write-Host "Deploying Database Change Explorer to GKE..." -ForegroundColor Yellow
Write-Host "  Project: $ProjectId" -ForegroundColor Gray
Write-Host "  Registry: $Region-docker.pkg.dev/$ProjectId/$RepoName" -ForegroundColor Gray

# Navigate to project root
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Join-Path $scriptDir ".." | Join-Path -ChildPath "..")

$registry = "$Region-docker.pkg.dev/$ProjectId/$RepoName"

# Verify kubectl is configured for GKE
Write-Host "`nVerifying GKE cluster connection..." -ForegroundColor Cyan
kubectl cluster-info | Select-String "Kubernetes control plane"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: kubectl not configured for GKE cluster" -ForegroundColor Red
    Write-Host "Run: gcloud container clusters get-credentials db-explorer --region=$Region" -ForegroundColor Yellow
    exit 1
}

# Create namespace unless skipped
if (-not $SkipNamespace) {
    Write-Host "`nCreating namespace db-explorer..." -ForegroundColor Cyan
    kubectl create namespace db-explorer 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Namespace created" -ForegroundColor Green
    } else {
        Write-Host "Namespace already exists (OK)" -ForegroundColor Yellow
    }
}

# Deploy services in dependency order
$services = @(
    @{Name="postgres"; Chart="services/postgres/chart/postgres-0.1.0.tgz"; Wait=120; Image=$null},
    @{Name="kafka"; Chart="services/kafka/chart/kafka-0.1.0.tgz"; Wait=120; Image=$null},
    @{Name="clickhouse"; Chart="services/clickhouse/chart/clickhouse-0.1.0.tgz"; Wait=120; Image=$null},
    @{Name="debezium"; Chart="services/debezium/chart/debezium-0.1.0.tgz"; Wait=120; Image=$null},
    @{Name="dev01-consumer"; Chart="services/dev01-consumer-service/chart/dev01-consumer-service-0.1.0.tgz"; Wait=90; Image="$registry/dev01-consumer-service:1.0.0"},
    @{Name="ml"; Chart="services/ml/chart/ml-0.1.0.tgz"; Wait=60; Image="$registry/ml-inference:latest"},
    @{Name="backend"; Chart="services/backend/chart/backend-0.1.0.tgz"; Wait=60; Image="$registry/backend-api:latest"},
    @{Name="tabix"; Chart="services/tabix/chart/tabix-0.1.0.tgz"; Wait=60; Image=$null},
    @{Name="grafana"; Chart="services/grafana/chart/grafana-0.1.0.tgz"; Wait=120; Image=$null}
)

foreach ($svc in $services) {
    Write-Host "`nDeploying $($svc.Name)..." -ForegroundColor Cyan
    
    # Build helm upgrade command with image override if needed
    $helmCmd = "helm upgrade --install $($svc.Name) $($svc.Chart) -n db-explorer"
    if ($svc.Image) {
        # Extract repository and tag from the full image path
        $imageParts = $svc.Image -split ":"
        $imageRepo = $imageParts[0]
        $imageTag = $imageParts[1]
        $helmCmd += " --set image.repository=$imageRepo --set image.tag=$imageTag"
    }
    
    # Execute helm command
    Invoke-Expression $helmCmd
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to deploy $($svc.Name)" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Waiting for $($svc.Name) to be ready..." -ForegroundColor Gray
    
    # Use different label for dev01-consumer (chart name vs app label)
    $labelSelector = if ($svc.Name -eq "dev01-consumer") { "app=dev01-consumer-service" } else { "app=$($svc.Name)" }
    kubectl wait --for=condition=ready pod -l $labelSelector -n db-explorer --timeout="$($svc.Wait)s" 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$($svc.Name) deployed and ready" -ForegroundColor Green
    } else {
        Write-Host "$($svc.Name) deployed but not ready yet (may still be starting)" -ForegroundColor Yellow
    }
}

Write-Host "`nDeployment Complete!" -ForegroundColor Green

Write-Host "`nCheck CDC Consumer Status:" -ForegroundColor Yellow
Write-Host "  kubectl logs -n db-explorer -l app=dev01-consumer-service -f" -ForegroundColor White
Write-Host ""

Write-Host "`nVerifying deployment..." -ForegroundColor Cyan
kubectl get pods -n db-explorer

Write-Host "`nAccess the services:" -ForegroundColor Yellow
Write-Host "  Streamlit Dashboard (Main UI - run locally):" -ForegroundColor Cyan
Write-Host "    cd streamlit" -ForegroundColor White
Write-Host "    streamlit run app.py" -ForegroundColor White
Write-Host "    http://localhost:8501" -ForegroundColor Gray
Write-Host ""
Write-Host "  Backend API (REST endpoints):" -ForegroundColor Cyan
Write-Host "    kubectl port-forward -n db-explorer svc/backend 8000:8000" -ForegroundColor White
Write-Host "    http://localhost:8000/docs" -ForegroundColor Gray
Write-Host ""
Write-Host "  pgAdmin (Data Manipulation):" -ForegroundColor Yellow
Write-Host "    kubectl port-forward -n db-explorer svc/pgadmin 8081:80" -ForegroundColor White
Write-Host "    http://localhost:8081 (admin@local.com / admin123)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Grafana (Developer Monitoring):" -ForegroundColor Yellow
Write-Host "    kubectl port-forward -n db-explorer svc/grafana 3000:3000" -ForegroundColor White
Write-Host "    http://localhost:3000 (admin / admin123)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Tabix (SQL Investigation):" -ForegroundColor Yellow
Write-Host "    kubectl port-forward -n db-explorer svc/tabix 8080:80" -ForegroundColor White
Write-Host "    http://localhost:8080" -ForegroundColor Gray

Write-Host "`nFor live demo instructions, see DEMO.md" -ForegroundColor Cyan
