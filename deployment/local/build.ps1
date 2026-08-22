#!/usr/bin/env pwsh
# build.ps1 - Package all Helm charts and build Docker images

Write-Host "Building Database Change Explorer Helm Charts..." -ForegroundColor Yellow

# Navigate to project root
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Join-Path $scriptDir ".." | Join-Path -ChildPath "..")

# Build Docker images
Write-Host "`nBuilding Docker images..." -ForegroundColor Cyan

# ML inference image
Write-Host "Building ML inference image..." -ForegroundColor Gray
Push-Location services/ml
docker build -t ml-inference:latest .
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to build ML Docker image" -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location
Write-Host "ML image built successfully" -ForegroundColor Green

# Backend API image
Write-Host "Building Backend API image..." -ForegroundColor Gray
Push-Location services/backend
docker build -t backend-api:latest .
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to build Backend Docker image" -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location
Write-Host "Backend image built successfully" -ForegroundColor Green

# dev01-consumer-service (Java/Maven)
Write-Host "Building dev01-consumer-service image..." -ForegroundColor Gray
Push-Location services/dev01-consumer-service
Write-Host "  Running Maven build..." -ForegroundColor Gray
mvn clean package -DskipTests
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to build Maven project" -ForegroundColor Red
    Pop-Location
    exit 1
}
Write-Host "  Building Docker image..." -ForegroundColor Gray
docker build -t dev01-consumer-service:1.0.0 .
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to build dev01-consumer-service Docker image" -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location
Write-Host "dev01-consumer-service image built successfully" -ForegroundColor Green

# Package Helm charts
$services = @("postgres", "kafka", "clickhouse", "debezium", "dev01-consumer-service", "ml", "backend", "tabix", "pgadmin", "grafana")

foreach ($service in $services) {
    Write-Host "`nPackaging $service..." -ForegroundColor Cyan
    Push-Location "services/$service/chart"
    
    helm package .
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Package created successfully" -ForegroundColor Green
    } else {
        Write-Host "Failed to package $service" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Pop-Location
}

Write-Host "`nBuild complete! All charts packaged and Docker images built." -ForegroundColor Green
