terraform {
  required_version = ">= 1.10.0" # S3 native state locking (use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Remote state in S3 with native state locking (Terraform >= 1.10, no DynamoDB).
  # The bucket is created once out-of-band by scripts/bootstrap.sh — a backend
  # can't create the bucket it stores its state in.
  backend "s3" {
    bucket       = "tam-server-node-tfstate"
    key          = "tam-server-node/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
