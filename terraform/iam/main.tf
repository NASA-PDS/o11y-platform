data "aws_caller_identity" "current" {}

locals {
  module_relative_path = replace(abspath(path.module), "/^.*\\/terraform\\//", "")
  ssm_prefix           = "/pds/o11y-platform/${local.module_relative_path}"

  # ARN is deterministic, so it can be published to SSM before the opensearch module
  # deploys — same pattern as o11y-cloudfront-streaming iam/ publishing kinesis_stream_arn.
  opensearch_cognito_role_arn = "arn:${var.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.domain_name}-opensearch-cognito"
}

# IAM role that allows the OpenSearch service to call Cognito APIs for Dashboards auth.
# Requires iam:CreateRole — deploy this module with a role that has IAM permissions,
# before deploying opensearch/ with dashboards_enabled = true.
resource "aws_iam_role" "opensearch_cognito" {
  name = "${var.domain_name}-opensearch-cognito"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "es.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "opensearch_cognito" {
  role       = aws_iam_role.opensearch_cognito.name
  policy_arn = "arn:${var.partition}:iam::aws:policy/AmazonOpenSearchServiceCognitoAccess"
}
