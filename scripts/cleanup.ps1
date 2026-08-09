#!/usr/bin/env pwsh
# cleanup.ps1 - Remove all Database Change Explorer services

Write-Host "Cleaning up Database Change Explorer..." -ForegroundColor Yellow

Write-Host "`nDeleting namespace db-explorer (this will remove all services)..." -ForegroundColor Cyan
kubectl delete namespace db-explorer

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nWaiting for namespace deletion to complete..." -ForegroundColor Gray
    kubectl wait --for=delete namespace/db-explorer --timeout=120s
    
    Write-Host "`nCleanup complete! All resources removed." -ForegroundColor Green
} else {
    Write-Host "`nNamespace may not exist or already deleted." -ForegroundColor Yellow
}
