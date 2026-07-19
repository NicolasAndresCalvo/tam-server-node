variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Short name used to prefix and tag resources."
  type        = string
  default     = "tam-server-node"
}

variable "environment" {
  description = "Deployment environment (dev/staging/prod)."
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones (public+private subnet pairs)."
  type        = number
  default     = 2
}

variable "container_port" {
  description = "Port the app listens on inside the container."
  type        = number
  default     = 3000
}

variable "desired_count" {
  description = "Number of ECS tasks to run."
  type        = number
  default     = 2
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory in MiB."
  type        = number
  default     = 512
}

variable "image_tag" {
  description = "Container image tag to deploy. CD overrides this; 'bootstrap' seeds the first apply before any image exists."
  type        = string
  default     = "bootstrap"
}

variable "domain_name" {
  description = "Optional. FQDN for the app (e.g. app.example.com). If set AND route53_zone_id is set, provisions ACM + HTTPS:443 with HTTP->HTTPS redirect. If empty, the ALB serves plain HTTP:80."
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Optional. Route53 hosted zone ID for domain_name. Required for automatic ACM DNS validation + alias record."
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repo (owner/name) allowed to assume the CI/CD role via OIDC. Empty disables the OIDC role."
  type        = string
  default     = ""
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false to reuse an existing one in the account."
  type        = bool
  default     = true
}
