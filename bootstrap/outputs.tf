output "state_bucket_name" {
  value = aws_s3_bucket.tf_state.bucket
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}