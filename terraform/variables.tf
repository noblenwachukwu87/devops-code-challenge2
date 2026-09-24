variable "project_name" {
  default = "devops-challenge2"
}

variable "cluster_name" {
  default = "devops-challenge2-cluster"
}

variable "vpc_cidr" {
  default = "10.1.0.0/16"
}

variable "azs" {
  default = ["us-east-1a", "us-east-1b"]
}

