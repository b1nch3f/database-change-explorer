#!/usr/bin/env pwsh
# deploy.ps1 - Deploy all Database Change Explorer services

param(
    [switch]$SkipNamespace
)

Write-Host "Deploying Database Change Explorer..." -ForegroundColor Yellow

# Navigate to project root
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Join-Path $scriptDir "..")

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
    @{Name="ml"; Chart="services/ml/chart/ml-0.1.0.tgz"; Wait=60},
    @{Name="backend"; Chart="services/backend/chart/backend-0.1.0.tgz"; Wait=60},
    @{Name="frontend"; Chart="services/frontend/chart/frontend-0.1.0.tgz"; Wait=60},
    @{Name="tabix"; Chart="services/tabix/chart/tabix-0.1.0.tgz"; Wait=60},
    @{Name="pgadmin"; Chart="services/pgadmin/chart/pgadmin-0.1.0.tgz"; Wait=120},
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
    kubectl wait --for=condition=ready pod -l app=$svc.Name -n db-explorer --timeout="$($svc.Wait)s" 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$($svc.Name) deployed and ready" -ForegroundColor Green
    } else {
        Write-Host "$($svc.Name) deployed but not ready yet (may still be starting)" -ForegroundColor Yellow
    }
}

Write-Host "`nDeployment Complete!" -ForegroundColor Green

Write-Host "`nVerifying deployment..." -ForegroundColor Cyan
kubectl get pods -n db-explorer

Write-Host "`nAccess the UIs:" -ForegroundColor Yellow
Write-Host "  Frontend Dashboard (Main UI):" -ForegroundColor Cyan
Write-Host "    kubectl port-forward -n db-explorer svc/frontend 3001:3000" -ForegroundColor White
Write-Host "    http://localhost:3001" -ForegroundColor Gray
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
