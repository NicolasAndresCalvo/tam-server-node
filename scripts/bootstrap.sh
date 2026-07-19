#!/usr/bin/env bash
# One-time, out-of-band bootstrap for the CI-driven Terraform pipeline.
#
# Creates the three things that MUST exist before any pipeline can run Terraform:
#   1. S3 state bucket        (a backend can't create the bucket it lives in)
#   2. GitHub OIDC provider   (only one per account is allowed)
#   3. TF-runner IAM role     (the role terraform.yml assumes to apply infra)
#
# After this, everything is pipeline-driven: terraform.yml applies the infra
# (and creates the scoped app-deploy role), deploy.yml ships the app. No local
# apply needed.
#
# Run ONCE per account, with admin credentials. Idempotent — safe to re-run.
#
# Usage:  AWS_PROFILE=min ./scripts/bootstrap.sh
set -euo pipefail

BUCKET="${STATE_BUCKET:-tam-server-node-tfstate}"
REGION="${AWS_REGION:-eu-west-1}"
REPO="${GITHUB_REPO:-NicolasAndresCalvo/tam-server-node}"
TF_ROLE_NAME="${TF_ROLE_NAME:-tam-server-node-tf-runner}"
OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
OIDC_HOST="token.actions.githubusercontent.com"
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_HOST}"

echo "Account: $ACCOUNT_ID | Region: $REGION | Repo: $REPO"

# ---------------------------------------------------------------------------
# 1. State bucket (versioned, encrypted, private)
# ---------------------------------------------------------------------------
echo "==> State bucket '$BUCKET'"
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "    exists — skip create"
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
  echo "    created"
fi
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# ---------------------------------------------------------------------------
# 2. GitHub OIDC provider (one per account)
# ---------------------------------------------------------------------------
echo "==> OIDC provider $OIDC_HOST"
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  echo "    exists — skip create"
else
  aws iam create-open-id-connect-provider \
    --url "https://${OIDC_HOST}" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" >/dev/null
  echo "    created"
fi

# ---------------------------------------------------------------------------
# 3. TF-runner role — assumed by terraform.yml via OIDC to provision infra.
#    Broad by nature (it manages the whole stack). In a real org this would
#    carry a permissions boundary; kept simple here and documented as such.
# ---------------------------------------------------------------------------
echo "==> TF-runner role '$TF_ROLE_NAME'"
TRUST=$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "$OIDC_ARN" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "${OIDC_HOST}:aud": "sts.amazonaws.com" },
      "StringLike":   { "${OIDC_HOST}:sub": [
        "repo:${REPO}:*",
        "repo:${OWNER}@*/${NAME}@*:*"
      ]}
    }
  }]
}
JSON
)

if aws iam get-role --role-name "$TF_ROLE_NAME" >/dev/null 2>&1; then
  echo "    exists — updating trust policy"
  aws iam update-assume-role-policy --role-name "$TF_ROLE_NAME" \
    --policy-document "$TRUST"
else
  aws iam create-role --role-name "$TF_ROLE_NAME" \
    --description "GitHub Actions runs Terraform for tam-server-node" \
    --assume-role-policy-document "$TRUST" >/dev/null
  echo "    created"
fi
# Privileged: this role provisions VPC/IAM/ELB/ECS/etc. Harden with a
# permissions boundary in production.
aws iam attach-role-policy --role-name "$TF_ROLE_NAME" \
  --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

echo ""
echo "Bootstrap complete. Set these GitHub secrets:"
echo "  AWS_TF_ROLE_ARN  = arn:aws:iam::${ACCOUNT_ID}:role/${TF_ROLE_NAME}"
echo "  AWS_GHA_ROLE_ARN = arn:aws:iam::${ACCOUNT_ID}:role/tam-server-node-prod-gha  (exists after first terraform apply)"
