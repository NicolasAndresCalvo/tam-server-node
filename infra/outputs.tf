output "app_url" {
  description = "Public URL of the application."
  value       = local.enable_tls ? "https://${var.domain_name}" : "http://${aws_lb.this.dns_name}"
}

output "alb_dns_name" {
  description = "ALB DNS name (use this if no custom domain)."
  value       = aws_lb.this.dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for the app image."
  value       = aws_ecr_repository.this.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "ecs_service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.this.name
}

output "github_actions_role_arn" {
  description = "IAM role ARN GitHub Actions assumes via OIDC (empty if github_repo unset)."
  value       = local.enable_oidc ? aws_iam_role.ci[0].arn : ""
}
