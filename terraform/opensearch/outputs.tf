resource "aws_ssm_parameter" "opensearch_endpoint" {
  name        = "${local.ssm_prefix}/opensearch_endpoint"
  type        = "String"
  value       = aws_opensearch_domain.this.endpoint
  description = "Managed OpenSearch domain endpoint"
}

resource "aws_ssm_parameter" "opensearch_arn" {
  name        = "${local.ssm_prefix}/opensearch_arn"
  type        = "String"
  value       = aws_opensearch_domain.this.arn
  description = "Managed OpenSearch domain ARN — consumed by web-analytics IAM policy"
}

output "opensearch_endpoint" {
  value       = aws_opensearch_domain.this.endpoint
  description = "Managed OpenSearch domain endpoint URL — published to /pds/observability/opensearch/opensearch_endpoint"
}

output "opensearch_domain_name" {
  value       = aws_opensearch_domain.this.domain_name
  description = "Managed OpenSearch domain name (Terraform output only, not published to SSM)"
}

output "opensearch_arn" {
  value       = aws_opensearch_domain.this.arn
  description = "Managed OpenSearch domain ARN — published to /pds/observability/opensearch/opensearch_arn"
}
