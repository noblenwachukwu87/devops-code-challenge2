
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "devops-challenge2"
}

variable "cluster_name" {
  type    = string
  default = "devops-challenge2-cluster"
}

variable "vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "single_nat_gateway" {
  description = "true = one NAT (cost-saving demo). false = one NAT per AZ (production)."
  type        = bool
  default     = true
}

variable "cluster_version" {
  type    = string
  default = "1.36"
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
