data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "ec2_role_arn" {
  name = "/pds/web-analytics/iam/ec2_role_arn"
}

data "aws_ssm_parameter" "cloudfront_realtime_firehose_role_arn" {
  name = "/pds/monitor/firehose/firehose-role-arn"
}

data "aws_security_group" "mcp_ec2" {
  count  = var.vpc_enabled ? 1 : 0
  name   = var.ec2_security_group_name
  vpc_id = var.vpc_id
}

locals {
  module_relative_path = replace(abspath(path.module), "/^.*\\/terraform\\//", "")
  ssm_prefix           = "/pds/observability/${local.module_relative_path}"
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

  ingress {
    description     = "Allow HTTPS from the CloudFront real-time logging Firehose security group."
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [var.firehose_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "${var.domain_name}-opensearch-sg"
    venue     = var.venue
    tenant    = var.tenant
    component = var.component
    managedby = var.managedby
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_opensearch_domain" "pds_opensearch_domain" {
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
    enabled = var.n2n_encryption
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  advanced_security_options {
    enabled = false
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


resource "aws_opensearch_domain_policy" "domain_access_policy" {
  domain_name = var.domain_name
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEC2AndFirehose"
        Effect = "Allow"
        Principal = {
          AWS = [
            data.aws_ssm_parameter.ec2_role_arn.value,
            data.aws_ssm_parameter.cloudfront_realtime_firehose_role_arn.value,
          ]
        }
        Action = "es:*"
        Resource = [
          "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${var.domain_name}",
          "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${var.domain_name}/*",
        ]
      }
    ]
  })

  depends_on = [aws_opensearch_domain.pds_opensearch_domain]
}
