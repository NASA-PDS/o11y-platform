resource "aws_ssm_parameter" "opensearch_cognito_role_arn" {
  name        = "${local.ssm_prefix}/opensearch_cognito_role_arn"
  type        = "String"
  value       = aws_iam_role.opensearch_cognito.arn
  description = "ARN of the OpenSearch→Cognito IAM service role — read by opensearch/ when dashboards_enabled = true"
}

output "opensearch_cognito_role_arn" {
  value       = aws_iam_role.opensearch_cognito.arn
  description = "ARN of the OpenSearch→Cognito IAM service role — published to /pds/o11y-platform/iam/opensearch_cognito_role_arn"
}
