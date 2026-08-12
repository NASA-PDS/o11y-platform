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

resource "aws_ssm_parameter" "opensearch_security_group_id" {
  count       = var.vpc_enabled ? 1 : 0
  name        = "${local.ssm_prefix}/opensearch_security_group_id"
  type        = "String"
  value       = aws_security_group.opensearch[0].id
  description = "OpenSearch domain VPC security group ID — consumed by cf-realtime-monitor to add a Firehose ingress rule"
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

output "opensearch_security_group_id" {
  value       = var.vpc_enabled ? aws_security_group.opensearch[0].id : null
  description = "OpenSearch domain VPC security group ID — published to /pds/observability/opensearch/opensearch_security_group_id when vpc_enabled"
}
