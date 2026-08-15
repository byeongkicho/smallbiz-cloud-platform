output "gha_role_arn" {
  description = "GitHub Actions 워크플로의 role-to-assume에 넣을 ARN"
  value       = aws_iam_role.gha_terraform_plan.arn
}

output "oidc_provider_arn" {
  description = "GitHub Actions OIDC 공급자 ARN"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "trusted_subjects" {
  description = "이 역할을 수임할 수 있는 OIDC subject (이 목록 밖은 전부 거부)"
  value = [
    "repo:${var.github_repository}:pull_request",
    "repo:${var.github_repository}:ref:refs/heads/main",
  ]
}
