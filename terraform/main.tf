module "network" {
  source = "./modules/network"

  project_name       = var.project_name
  cluster_name       = var.cluster_name
  vpc_cidr           = var.vpc_cidr
  azs                = var.azs
  single_nat_gateway = var.single_nat_gateway
}

module "eks" {
  source = "./modules/eks"

  project_name    = var.project_name
  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_subnet_ids         = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  node_subnet_ids            = module.network.private_subnet_ids
  cluster_security_group_ids = [module.network.cluster_security_group_id]

  node_instance_types = var.node_instance_types
  node_min_size       = var.node_min_size
  node_desired_size   = var.node_desired_size
  node_max_size       = var.node_max_size
}