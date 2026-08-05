resource "aws_ssm_parameter" "opensearch_endpoint" {
  name        = "${local.ssm_prefix}/opensearch_endpoint"
  type        = "String"
  value       = aws_opensearch_domain.pds_opensearch_domain.endpoint
  description = "Managed OpenSearch domain endpoint"
  overwrite   = true
}

resource "aws_ssm_parameter" "opensearch_arn" {
  name        = "${local.ssm_prefix}/opensearch_arn"
  type        = "String"
  value       = aws_opensearch_domain.pds_opensearch_domain.arn
  description = "Managed OpenSearch domain ARN — consumed by web-analytics IAM policy"
  overwrite   = true
}

output "opensearch_endpoint" {
  value       = aws_opensearch_domain.pds_opensearch_domain.endpoint
  description = "Managed OpenSearch domain endpoint URL"
}

output "opensearch_domain_name" {
  value       = aws_opensearch_domain.pds_opensearch_domain.domain_name
  description = "Managed OpenSearch domain name"
}
