variable "project_name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "cluster_version" {
  description = "Kubernetes version for the control plane"
  type        = string
  default     = "1.36"
}

variable "cluster_subnet_ids" {
  description = "Subnets for the control plane ENIs (public + private)"
  type        = list(string)
}

variable "node_subnet_ids" {
  description = "Private subnets for worker nodes"
  type        = list(string)
}

variable "cluster_security_group_ids" {
  type = list(string)
}

variable "endpoint_public_access_cidrs" {
  description = "Who can reach the Kubernetes API from the internet"
  type        = list(string)
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.small"]
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}