# Bootstrap

`bootstrap.sh` creates the few things that **must exist before any pipeline can
run Terraform** — the classic chicken-and-egg problem: the Terraform S3 backend
can't create the bucket it stores its own state in, and GitHub Actions can't
authenticate to AWS until an OIDC trust and a role exist.

It is the **only** step that needs human/admin credentials. Everything after it
runs in the pipeline via short-lived OIDC tokens — no long-lived AWS keys.

## What it creates

| # | Resource | Why it can't be in Terraform |
|---|---|---|
| 1 | **S3 state bucket** (versioned, encrypted, private) | A backend can't create the bucket that holds its state. Locking uses S3's native lockfile (Terraform ≥ 1.10) — no DynamoDB. |
| 2 | **GitHub OIDC provider** | Only one per AWS account; shared by all repos, so it's created once out-of-band. |
| 3 | **TF-runner IAM role** (`tam-server-node-tf-runner`) | The role `terraform.yml` assumes via OIDC to provision the stack. It needs broad rights (it manages VPC/IAM/ELB/ECS), so it must pre-exist the config it applies. |

The narrower, least-privilege **app-deploy** role (`tam-server-node-prod-gha`,
used by `deploy.yml`) is *not* here — Terraform creates it (see `infra/oidc.tf`),
because by then Terraform is running.

## Prerequisites

- AWS CLI v2, authenticated with **admin** credentials for the target account
  (e.g. `aws sso login --profile <profile>`).
- The GitHub repo the workflows run from.

## Usage

Run once per AWS account. The script is idempotent — safe to re-run.

```bash
AWS_PROFILE=<profile> ./scripts/bootstrap.sh
```

Override defaults with env vars if needed:

```bash
STATE_BUCKET=my-tfstate \
REGION=eu-west-1 \
GITHUB_REPO=owner/name \
TF_ROLE_NAME=my-tf-runner \
AWS_PROFILE=<profile> ./scripts/bootstrap.sh
```

## After running

The script prints two role ARNs. Add them as **GitHub Actions repository
secrets**:

| Secret | Value |
|---|---|
| `AWS_TF_ROLE_ARN` | `tam-server-node-tf-runner` role ARN — used by `terraform.yml` |
| `AWS_GHA_ROLE_ARN` | `tam-server-node-prod-gha` role ARN — used by `deploy.yml`. Exists only **after** the first `terraform apply` (`terraform output github_actions_role_arn`). |

Then the flow is fully pipeline-driven:

1. `terraform.yml` (manual dispatch → `apply`) provisions the infrastructure and
   creates the scoped app-deploy role.
2. `deploy.yml` (push to `main` / manual) builds the image, pushes to ECR, and
   rolls the ECS service.

## Teardown

Infra: run `terraform.yml` with the `destroy` action (or `terraform destroy`
locally). The three bootstrap resources are intentionally **not** destroyed by
Terraform — remove them by hand if you're fully decommissioning:

```bash
aws s3 rb s3://tam-server-node-tfstate --force
aws iam delete-role --role-name tam-server-node-tf-runner   # detach policies first
# leave the OIDC provider if any other repo/stack uses it
```
