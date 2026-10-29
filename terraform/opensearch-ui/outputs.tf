output "application_id" {
  value       = aws_opensearch_application.this.id
  description = "OpenSearch UI application ID"
}

output "application_arn" {
  value       = aws_opensearch_application.this.arn
  description = "OpenSearch UI application ARN"
}

output "application_endpoint" {
  value       = aws_opensearch_application.this.endpoint
  description = "OpenSearch UI application URL"
}
