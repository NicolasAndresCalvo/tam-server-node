# Shared locals + account/AZ lookups used across the flat config.
# The stack is small enough that flat files (network / alb / ecs / ecr / oidc)
# read more directly than a module tree. See docs/decisions.md for the
# "started modular, flattened it" note and the portability trade-off.

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name        = "${var.project_name}-${var.environment}"
  azs         = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  enable_tls  = var.domain_name != "" && var.route53_zone_id != ""
  enable_oidc = var.github_repo != ""
}
