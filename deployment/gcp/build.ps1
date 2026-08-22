#!/usr/bin/env pwsh
# build.ps1 - Build and push Docker images to GCP Artifact Registry, package Helm charts

param(
    [string]$ProjectId = "database-change-explorer",
    [string]$Region = "asia-south1",
    [string]$RepoName = "db-explorer"
)

Write-Host "Building and pushing to GCP Artifact Registry..." -ForegroundColor Yellow
Write-Host "  Project: $ProjectId" -ForegroundColor Gray
Write-Host "  Region: $Region" -ForegroundColor Gray
Write-Host "  Repository: $RepoName" -ForegroundColor Gray

# Navigate to project root
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Join-Path $scriptDir ".." | Join-Path -ChildPath "..")

$registry = "$Region-docker.pkg.dev/$ProjectId/$RepoName"

# Create Artifact Registry repository if it doesn't exist
Write-Host "`nCreating Artifact Registry repository (if needed)..." -ForegroundColor Cyan
gcloud artifacts repositories create $RepoName `
    --repository-format=docker `
    --location=$Region `
    --description="Database Change Explorer Docker images" 2>$null

if ($LASTEXITCODE -eq 0) {
    Write-Host "Repository created successfully" -ForegroundColor Green
} else {
    Write-Host "Repository already exists (OK)" -ForegroundColor Yellow
}

# Configure Docker to use gcloud as credential helper
Write-Host "`nConfiguring Docker authentication..." -ForegroundColor Cyan
gcloud auth configure-docker "$Region-docker.pkg.dev" --quiet

# Build and push Docker images
Write-Host "`nBuilding and pushing Docker images..." -ForegroundColor Cyan

# ML inference image
Write-Host "`nBuilding ML inference image..." -ForegroundColor Gray
Push-Location services/ml
docker build -t ml-inference:latest .
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to build ML Docker image" -ForegroundColor Red
    Pop-Location
    exit 1
}
docker tag ml-inference:latest "$registry/ml-inference:latest"
docker push "$registry/ml-inference:latest"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to push ML image" -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location
Write-Host "ML image built and pushed successfully" -ForegroundColor Green

# Backend API image
Write-Host "`nBuilding Backend API image..." -ForegroundColor Gray
Push-Location services/backend
docker build -t backend-api:latest .
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to build Backend Docker image" -ForegroundColor Red
    Pop-Location
    exit 1
}
docker tag backend-api:latest "$registry/backend-api:latest"
docker push "$registry/backend-api:latest"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to push Backend image" -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location
Write-Host "Backend image built and pushed successfully" -ForegroundColor Green

# dev01-consumer-service (Java/Maven)
Write-Host "`nBuilding dev01-consumer-service image..." -ForegroundColor Gray
Push-Location services/dev01-consumer-service
docker build -t dev01-consumer-service:1.0.0 .
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to build dev01-consumer-service Docker image" -ForegroundColor Red
    Pop-Location
    exit 1
}
docker tag dev01-consumer-service:1.0.0 "$registry/dev01-consumer-service:1.0.0"
docker push "$registry/dev01-consumer-service:1.0.0"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to push dev01-consumer-service image" -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location
Write-Host "dev01-consumer-service image built and pushed successfully" -ForegroundColor Green

# Package Helm charts
Write-Host "`nPackaging Helm charts..." -ForegroundColor Cyan
$services = @("postgres", "kafka", "clickhouse", "debezium", "dev01-consumer-service", "ml", "backend", "tabix", "pgadmin", "grafana")

foreach ($service in $services) {
    Write-Host "  Packaging $service..." -ForegroundColor Gray
    Push-Location "services/$service/chart"
    
    helm package . 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  $service packaged successfully" -ForegroundColor Green
    } else {
        Write-Host "Failed to package $service" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Pop-Location
}

Write-Host "`nBuild complete!" -ForegroundColor Green
Write-Host "  All images pushed to: $registry" -ForegroundColor Cyan
Write-Host "  All Helm charts packaged" -ForegroundColor Cyan
Write-Host "`nNext step: .\scripts\gcp\deploy.ps1" -ForegroundColor Yellow
