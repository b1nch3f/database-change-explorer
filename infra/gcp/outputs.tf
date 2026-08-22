# GCP Infrastructure Outputs

output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.db_explorer.name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.db_explorer.endpoint
  sensitive   = true
}

output "cluster_location" {
  description = "GKE cluster location"
  value       = google_container_cluster.db_explorer.location
}

output "registry_url" {
  description = "Artifact Registry URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.registry_name}"
}

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${var.cluster_name} --region=${var.region}"
}

output "docker_auth_command" {
  description = "Command to configure Docker authentication"
  value       = "gcloud auth configure-docker ${var.region}-docker.pkg.dev"
}
