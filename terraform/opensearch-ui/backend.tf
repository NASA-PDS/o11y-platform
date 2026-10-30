# Backend configuration for S3 state storage.
# The key is pinned here. Bucket, region, and lock settings are supplied at
# init time by Terragrunt in cds-infra-deploy.

terraform {
  backend "s3" {
    key = "o11y-platform/opensearch-ui.tfstate"
  }
}
