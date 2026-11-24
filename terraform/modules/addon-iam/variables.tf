variable "project_name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "lbc_service_account" {
  type    = string
  default = "aws-load-balancer-controller"
}

variable "cluster_autoscaler_service_account" {
  type    = string
  default = "cluster-autoscaler"
}