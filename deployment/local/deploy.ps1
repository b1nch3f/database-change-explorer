#!/usr/bin/env pwsh
# deploy.ps1 - Deploy all Database Change Explorer services

param(
    [switch]$SkipNamespace
)

Write-Host "Deploying Database Change Explorer..." -ForegroundColor Yellow

# Navigate to project root
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Join-Path $scriptDir ".." | Join-Path -ChildPath "..")

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
    @{Name="postgres"; Chart="services/postgres/chart/postgres-0.1.0.tgz"; Wait=120},
    @{Name="kafka"; Chart="services/kafka/chart/kafka-0.1.0.tgz"; Wait=120},
    @{Name="clickhouse"; Chart="services/clickhouse/chart/clickhouse-0.1.0.tgz"; Wait=120},
    @{Name="debezium"; Chart="services/debezium/chart/debezium-0.1.0.tgz"; Wait=120},
    @{Name="dev01-consumer"; Chart="services/dev01-consumer-service/chart/dev01-consumer-service-0.1.0.tgz"; Wait=90},
    @{Name="ml"; Chart="services/ml/chart/ml-0.1.0.tgz"; Wait=60},
    @{Name="backend"; Chart="services/backend/chart/backend-0.1.0.tgz"; Wait=60},
    @{Name="tabix"; Chart="services/tabix/chart/tabix-0.1.0.tgz"; Wait=60},
    @{Name="grafana"; Chart="services/grafana/chart/grafana-0.1.0.tgz"; Wait=120}
)

foreach ($svc in $services) {
    Write-Host "`nDeploying $($svc.Name)..." -ForegroundColor Cyan
    
    helm upgrade --install $svc.Name $svc.Chart -n db-explorer
    
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

Write-Host "Verifying deployment..." -ForegroundColor Cyan
kubectl get pods -n db-explorer

Write-Host "`nAccess the UIs:" -ForegroundColor Yellow
Write-Host "  Streamlit Dashboard (Main UI - run locally):" -ForegroundColor Cyan
Write-Host "    cd streamlit" -ForegroundColor White
Write-Host "    streamlit run app.py" -ForegroundColor White
Write-Host "    http://localhost:8501" -ForegroundColor Gray
Write-Host ""
Write-Host "  Backend API (REST endpoints):" -ForegroundColor Cyan
Write-Host "    kubectl port-forward -n db-explorer svc/backend 8000:8000" -ForegroundColor White
Write-Host "    http://localhost:8000/docs" -ForegroundColor Gray
Write-Host ""
Write-Host "  PostgreSQL (Database Access - use desktop client like DBeaver):" -ForegroundColor Yellow
Write-Host "    kubectl port-forward -n db-explorer svc/postgres 5432:5432" -ForegroundColor White
Write-Host "    localhost:5432 / sourcedb / dbuser / dbpass123" -ForegroundColor Gray
Write-Host ""
Write-Host "  Grafana (Developer Monitoring):" -ForegroundColor Yellow
Write-Host "    kubectl port-forward -n db-explorer svc/grafana 3000:3000" -ForegroundColor White
Write-Host "    http://localhost:3000 (admin / admin123)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Tabix (SQL Investigation):" -ForegroundColor Yellow
Write-Host "    kubectl port-forward -n db-explorer svc/tabix 8080:80" -ForegroundColor White
Write-Host "    http://localhost:8080" -ForegroundColor Gray

Write-Host "`nFor live demo instructions, see DEMO.md" -ForegroundColor Cyan
