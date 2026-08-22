# GCP Infrastructure Variables

variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "database-change-explorer"
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "asia-south1"
}

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
  default     = "db-explorer"
}

variable "registry_name" {
  description = "Artifact Registry repository name"
  type        = string
  default     = "db-explorer"
}
