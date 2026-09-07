# Backend configuration for S3 state storage.
# The key is pinned here. Bucket, region, and lock settings are supplied at
# init time — by Terragrunt in cds-infra-deploy for real deploys, or by
# -backend-config flags in terraform/Taskfile.yaml for local Task fallback.
#
# Do not add backend-*.hcl files in this module; they were removed when this
# repo switched to Terragrunt.

terraform {
  backend "s3" {
    key = "o11y-platform/opensearch.tfstate"
  }
}
