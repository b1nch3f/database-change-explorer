# Database Change Explorer - GCP Infrastructure
# Creates GKE Autopilot cluster and Artifact Registry for CDC pipeline

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable required APIs
resource "google_project_service" "container" {
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifact_registry" {
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# GKE Autopilot Cluster
resource "google_container_cluster" "db_explorer" {
  name     = var.cluster_name
  location = "${var.region}-b"  # Zonal cluster for lower cost
  
  # Autopilot mode - Google manages nodes, scaling, security
  enable_autopilot = true
  
  # Network configuration
  network    = "default"
  subnetwork = "default"
  
  # Release channel for automatic upgrades
  release_channel {
    channel = "REGULAR"
  }
  
  # IP allocation policy (required for Autopilot)
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "/17"
    services_ipv4_cidr_block = "/22"
  }
  
  # Addons
  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }
    http_load_balancing {
      disabled = false
    }
  }
  
  # Logging and monitoring
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }
  
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }
  
  depends_on = [google_project_service.container]
}

# Artifact Registry Repository for Docker images
resource "google_artifact_registry_repository" "db_explorer" {
  location      = var.region
  repository_id = var.registry_name
  description   = "Docker images for Database Change Explorer CDC pipeline"
  format        = "DOCKER"
  
  depends_on = [google_project_service.artifact_registry]
}
