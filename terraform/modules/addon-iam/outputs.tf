output "lbc_role_arn" {
  value = aws_iam_role.lbc.arn
}

output "cluster_autoscaler_role_arn" {
  value = aws_iam_role.cluster_autoscaler.arn
}