data "aws_caller_identity" "current" {}

# Only looked up once the consumer has actually deployed and published its role ARN —
# see web_analytics_enabled / realtime_monitor_enabled in variables.tf.
data "aws_ssm_parameter" "ec2_role_arn" {
  count = var.web_analytics_enabled ? 1 : 0
  name  = "/pds/web-analytics/iam/ec2_role_arn"
}

data "aws_ssm_parameter" "cloudfront_realtime_firehose_role_arn" {
  count = var.realtime_monitor_enabled ? 1 : 0
  name  = "/pds/web-analytics-realtime/firehose/firehose-role-arn"
}

data "aws_security_group" "mcp_ec2" {
  count  = var.vpc_enabled ? 1 : 0
  name   = var.ec2_security_group_name
  vpc_id = var.vpc_id
}

locals {
  module_relative_path = replace(abspath(path.module), "/^.*\\/terraform\\//", "")
  ssm_prefix           = "/pds/observability/${local.module_relative_path}"

  opensearch_access_principals = concat(
    var.web_analytics_enabled ? [data.aws_ssm_parameter.ec2_role_arn[0].value] : [],
    var.realtime_monitor_enabled ? [data.aws_ssm_parameter.cloudfront_realtime_firehose_role_arn[0].value] : [],
  )
}

# Security group for the OpenSearch domain VPC endpoint.
# Allows HTTPS inbound only from the Logstash EC2 security group.
# Only created when vpc_enabled = true.
resource "aws_security_group" "opensearch" {
  count       = var.vpc_enabled ? 1 : 0
  name        = "${var.domain_name}-opensearch-sg"
  description = "OpenSearch domain VPC endpoint - HTTPS inbound from Logstash EC2 only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTPS from Logstash EC2"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [data.aws_security_group.mcp_ec2[0].id]
  }

  # No inline Firehose ingress rule here — web-analytics-realtime manages its own
  # aws_vpc_security_group_ingress_rule against this SG's ID (read from SSM,
  # see outputs.tf), so it isn't gated by realtime_monitor_enabled.

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.domain_name}-opensearch-sg"
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_opensearch_domain" "this" {
  domain_name    = var.domain_name
  engine_version = var.engine_version

  cluster_config {
    instance_type  = var.data_node_instance_type
    instance_count = var.data_node_count

    dedicated_master_enabled = var.dedicated_master_enabled
    dedicated_master_type    = var.master_node_instance_type
    dedicated_master_count   = var.master_node_count

    zone_awareness_enabled = var.zone_awareness_enabled
    dynamic "zone_awareness_config" {
      for_each = var.zone_awareness_enabled ? [1] : []
      content {
        availability_zone_count = var.availability_zone_count
      }
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_type = var.ebs_volume_type
    volume_size = var.ebs_volume_gb
  }

  encrypt_at_rest {
    enabled = var.encryption_at_rest
  }

  node_to_node_encryption {
    enabled = var.node_to_node_encryption
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  # Fine-grained access control (FGAC) is intentionally disabled: access is restricted
  # to known IAM role ARNs via resource policy on a VPC-only domain, which is sufficient
  # for this use case. AUDIT_LOGS require FGAC to be enabled, so that log type is
  # unavailable here by design. #NOSONAR
  advanced_security_options {
    enabled = false #NOSONAR
  }

  dynamic "vpc_options" {
    for_each = var.vpc_enabled ? [1] : []
    content {
      subnet_ids         = var.vpc_subnet_ids
      security_group_ids = [aws_security_group.opensearch[0].id]
    }
  }

  tags = {
    Name = var.domain_name
  }
}



# Absent until at least one consumer is enabled (see web_analytics_enabled /
# realtime_monitor_enabled) — an access policy with an empty Principal.AWS is invalid,
# and on the initial bootstrap deploy neither consumer's role ARN exists in SSM yet.
resource "aws_opensearch_domain_policy" "this" {
  count       = length(local.opensearch_access_principals) > 0 ? 1 : 0
  domain_name = var.domain_name
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEC2AndFirehose"
        Effect = "Allow"
        Principal = {
          AWS = local.opensearch_access_principals
        }
        Action = "es:ESHttp*"
        Resource = [
          "arn:${var.partition}:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${var.domain_name}",
          "arn:${var.partition}:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${var.domain_name}/*",
        ]
      }
    ]
  })

  depends_on = [aws_opensearch_domain.this]
}
