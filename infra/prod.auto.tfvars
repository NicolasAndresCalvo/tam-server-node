# Non-secret prod config, committed so the CI pipeline uses it (auto-loaded by
# Terraform). No credentials or account IDs here — those come from the assumed
# role / provider. terraform.tfvars stays gitignored for local-only overrides.
aws_region   = "eu-west-1"
project_name = "tam-server-node"
environment  = "prod"

desired_count = 2
task_cpu      = 256
task_memory   = 512

# CI/CD: repo is public, auth is OIDC-federated (no keys).
github_repo          = "NicolasAndresCalvo/tam-server-node"
create_oidc_provider = false # provider already exists in the account (bootstrap)

# TLS via the existing Route53 zone (nicolasandrescalvo.com) in this account.
domain_name     = "tam.nicolasandrescalvo.com"
route53_zone_id = "Z02018991FA2099RMDMAY"
