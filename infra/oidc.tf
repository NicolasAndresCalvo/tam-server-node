# App-deploy CI role: GitHub Actions (deploy.yml) assumes this via OIDC to push
# an image and roll the ECS service. Scoped to THIS repo, ECR repo, and service.
# Distinct from the broad tf-runner role that scripts/bootstrap.sh creates.
# Everything here is gated on github_repo being set (local.enable_oidc).

# GitHub's OIDC provider — only one per account. Reuse an existing one
# (created by bootstrap.sh) when create_oidc_provider = false.
resource "aws_iam_openid_connect_provider" "github" {
  count           = local.enable_oidc && var.create_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = local.enable_oidc && !var.create_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = local.enable_oidc ? (
    var.create_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  ) : ""
}

data "aws_iam_policy_document" "ci_assume" {
  count = local.enable_oidc ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only workflows from this repo (any branch) may assume the role. Two patterns
    # cover both the classic subject and GitHub's immutable-ID subject format
    # (repo:owner@<ownerid>/name@<repoid>:...), which this account emits.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:*",
        "repo:${split("/", var.github_repo)[0]}@*/${split("/", var.github_repo)[1]}@*:*",
      ]
    }
  }
}

resource "aws_iam_role" "ci" {
  count              = local.enable_oidc ? 1 : 0
  name               = "${local.name}-gha"
  assume_role_policy = data.aws_iam_policy_document.ci_assume[0].json
}

# Least-privilege: push to this ECR repo, register task defs, update this service.
data "aws_iam_policy_document" "ci" {
  count = local.enable_oidc ? 1 : 0

  statement {
    sid       = "ECRAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this action does not support resource scoping
  }

  statement {
    sid = "ECRPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.this.arn]
  }

  statement {
    sid       = "ECSRegisterTaskDef"
    actions   = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition"]
    resources = ["*"] # RegisterTaskDefinition does not support resource-level scoping
  }

  statement {
    sid       = "ECSDeploy"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = [aws_ecs_service.this.id]
  }

  # Needed so the CD task def can reference the execution/task roles.
  statement {
    sid       = "PassRoles"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.execution.arn, aws_iam_role.task.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "ci" {
  count  = local.enable_oidc ? 1 : 0
  name   = "${local.name}-gha-policy"
  role   = aws_iam_role.ci[0].id
  policy = data.aws_iam_policy_document.ci[0].json
}
