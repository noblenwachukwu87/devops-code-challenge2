variable "aws_region" {
  description = "AWS region for bootstrap resources"
  type        = string
  default     = "us-east-1"
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the CI role (owner/name)"
  type        = string
  default     = "noblenwachukwu87/devops-code-challenge2"
}

variable "github_branch" {
  description = "Branch allowed to assume the CI role"
  type        = string
  default     = "production-upgrade"
}

variable "ecr_repository_name" {
  description = "ECR repository for the app image"
  type        = string
  default     = "devops-challenge2-app"
}

variable "github_owner_id" {
  description = "Immutable numeric ID of the GitHub owner (from the OIDC sub claim)"
  type        = string
  default     = "333077763"
}

variable "github_repo_id" {
  description = "Immutable numeric ID of the GitHub repo (from the OIDC sub claim)"
  type        = string
  default     = "1386175288"
}