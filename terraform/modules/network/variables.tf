variable "project_name" {
  type = string
}

variable "cluster_name" {
  description = "Used for the subnet tags the AWS Load Balancer Controller looks for"
  type        = string
}

variable "vpc_cidr" {
  type = string
}

variable "azs" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "true = one NAT for all AZs (cheaper). false = one NAT per AZ (production)."
  type        = bool
  default     = true
}