#!/usr/bin/env pwsh
# cleanup.ps1 - Remove all Database Change Explorer services from GKE

param(
    [string]$Region = "asia-south1",
    [switch]$DeleteCluster,
    [switch]$DeleteRegistry
)

Write-Host "Cleaning up Database Change Explorer from GKE..." -ForegroundColor Yellow

Write-Host "`nDeleting namespace db-explorer (this will remove all services)..." -ForegroundColor Cyan
kubectl delete namespace db-explorer

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nWaiting for namespace deletion to complete..." -ForegroundColor Gray
    kubectl wait --for=delete namespace/db-explorer --timeout=120s
    
    Write-Host "`nCleanup complete! All resources removed." -ForegroundColor Green
} else {
    Write-Host "`nNamespace may not exist or already deleted." -ForegroundColor Yellow
}

# Optionally delete the entire GKE cluster
if ($DeleteCluster) {
    Write-Host "`nDeleting GKE cluster db-explorer..." -ForegroundColor Red
    Write-Host "This will permanently delete the cluster. Are you sure? (y/N)" -ForegroundColor Yellow
    $confirmation = Read-Host
    
    if ($confirmation -eq 'y' -or $confirmation -eq 'Y') {
        gcloud container clusters delete db-explorer --region=$Region --quiet
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "GKE cluster deleted successfully" -ForegroundColor Green
        } else {
            Write-Host "Failed to delete GKE cluster" -ForegroundColor Red
        }
    } else {
        Write-Host "Cluster deletion cancelled" -ForegroundColor Yellow
    }
}

# Optionally delete the Artifact Registry repository
if ($DeleteRegistry) {
    Write-Host "`nDeleting Artifact Registry repository..." -ForegroundColor Red
    Write-Host "This will permanently delete all Docker images. Are you sure? (y/N)" -ForegroundColor Yellow
    $confirmation = Read-Host
    
    if ($confirmation -eq 'y' -or $confirmation -eq 'Y') {
        gcloud artifacts repositories delete db-explorer --location=$Region --quiet
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Artifact Registry repository deleted successfully" -ForegroundColor Green
        } else {
            Write-Host "Failed to delete Artifact Registry repository" -ForegroundColor Red
        }
    } else {
        Write-Host "Registry deletion cancelled" -ForegroundColor Yellow
    }
}

Write-Host "`nCleanup options:" -ForegroundColor Cyan
Write-Host "  To delete the entire GKE cluster: .\deployment\gcp\cleanup.ps1 -DeleteCluster" -ForegroundColor Gray
Write-Host "  To delete the Artifact Registry: .\deployment\gcp\cleanup.ps1 -DeleteRegistry" -ForegroundColor Gray
Write-Host "  To delete everything: .\deployment\gcp\cleanup.ps1 -DeleteCluster -DeleteRegistry" -ForegroundColor Gray
