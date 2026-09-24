output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "ecr_repository_url" {
  value = "491865087343.dkr.ecr.us-east-1.amazonaws.com/devops-challenge2-app"
}

