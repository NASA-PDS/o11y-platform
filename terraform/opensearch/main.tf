data "aws_caller_identity" "current" {}

# Only looked up once the consumer has actually deployed and published its role ARN —
# see o11y_cloudfront_batch_enabled / o11y_cloudfront_streaming_enabled in variables.tf.
data "aws_ssm_parameter" "ec2_role_arn" {
  count = var.o11y_cloudfront_batch_enabled ? 1 : 0
  name  = "/pds/o11y-cloudfront-batch/iam/ec2_role_arn"
}

data "aws_ssm_parameter" "firehose_role_arn" {
  count = var.o11y_cloudfront_streaming_enabled ? 1 : 0
  name  = "/pds/o11y-cloudfront-streaming/firehose/firehose-role-arn"
}

data "aws_security_group" "mcp_ec2" {
  count  = var.vpc_enabled ? 1 : 0
  name   = var.ec2_security_group_name
  vpc_id = var.vpc_id
}

data "aws_ssm_parameter" "firehose_security_group_id" {
  count = var.o11y_cloudfront_streaming_enabled ? 1 : 0
  name  = "/pds/o11y-cloudfront-streaming/firehose/firehose-security-group-id"
}

# Read Cognito resources provisioned by pdc-cds-infra. Only looked up when dashboards_enabled = true.
data "aws_ssm_parameter" "cognito_user_pool_id" {
  count = var.dashboards_enabled ? 1 : 0
  name  = "/pds/cds-infra/cognito/user-pool/user-pool-id"
}

data "aws_ssm_parameter" "cognito_identity_pool_id" {
  count = var.dashboards_enabled ? 1 : 0
  name  = "/pds/cds-infra/cognito/user-pool/opensearch-dashboards-identity-pool-id"
}

locals {
  module_relative_path = replace(abspath(path.module), "/^.*\\/terraform\\//", "")
  ssm_prefix           = "/pds/o11y-platform/${local.module_relative_path}"

  opensearch_access_principals = concat(
    var.o11y_cloudfront_batch_enabled ? [data.aws_ssm_parameter.ec2_role_arn[0].value] : [],
    var.o11y_cloudfront_streaming_enabled ? [data.aws_ssm_parameter.firehose_role_arn[0].value] : [],
    # Dashboards principal is the Cognito-authenticated admin role from pdc-cds-infra.
    # Required so Dashboards users can query the domain via FGAC.
    var.dashboards_enabled ? [data.aws_ssm_parameter.cognito_admin_role_arn[0].value] : [],
  )
}

data "aws_ssm_parameter" "cognito_admin_role_arn" {
  count = var.dashboards_enabled ? 1 : 0
  name  = "/pds/cds-infra/iam/roles/cognito-admin-role-arn"
}

# IAM service role for OpenSearch→Cognito — created by the o11y-platform iam/ module
# (separate deploy, requires iam:CreateRole permissions). Deploy iam/ first, then set
# dashboards_enabled = true here.
data "aws_ssm_parameter" "opensearch_cognito_role_arn" {
  count = var.dashboards_enabled ? 1 : 0
  name  = "/pds/o11y-platform/iam/opensearch_cognito_role_arn"
}

# Security group for the OpenSearch domain VPC endpoint.
# Ingress rules are managed as separate aws_vpc_security_group_ingress_rule resources
# to avoid mixing inline and standalone rules. Only created when vpc_enabled = true.
resource "aws_security_group" "opensearch" {
  count       = var.vpc_enabled ? 1 : 0
  name        = "${var.domain_name}-opensearch-sg"
  description = "OpenSearch domain VPC endpoint - HTTPS inbound only"
  vpc_id      = var.vpc_id

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

resource "aws_vpc_security_group_ingress_rule" "opensearch_https_from_ec2" {
  count                        = var.vpc_enabled ? 1 : 0
  security_group_id            = aws_security_group.opensearch[0].id
  referenced_security_group_id = data.aws_security_group.mcp_ec2[0].id

  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  description = "Allow HTTPS from the Logstash EC2 security group."
}

resource "aws_vpc_security_group_ingress_rule" "opensearch_https_from_firehose" {
  count                        = var.vpc_enabled && var.o11y_cloudfront_streaming_enabled ? 1 : 0
  security_group_id            = aws_security_group.opensearch[0].id
  referenced_security_group_id = data.aws_ssm_parameter.firehose_security_group_id[0].value

  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  description = "Allow HTTPS from the o11y-cloudfront-streaming Firehose security group."
}

resource "aws_opensearch_domain" "this" { #NOSONAR
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

  # FGAC is required when dashboards_enabled = true (Cognito auth for Dashboards requires it).
  # When disabled, access is restricted to known IAM role ARNs via resource policy only —
  # sufficient for ingest-only consumers. AUDIT_LOGS also require FGAC; unavailable when disabled.
  advanced_security_options {
    enabled                        = var.dashboards_enabled
    anonymous_auth_enabled         = false
    internal_user_database_enabled = false

    dynamic "master_user_options" {
      for_each = var.dashboards_enabled ? [1] : []
      content {
        master_user_arn = data.aws_ssm_parameter.cognito_admin_role_arn[0].value
      }
    }
  }

  dynamic "cognito_options" {
    for_each = var.dashboards_enabled ? [1] : []
    content {
      enabled          = true
      user_pool_id     = data.aws_ssm_parameter.cognito_user_pool_id[0].value
      identity_pool_id = data.aws_ssm_parameter.cognito_identity_pool_id[0].value
      role_arn         = data.aws_ssm_parameter.opensearch_cognito_role_arn[0].value
    }
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



# Absent until at least one consumer or dashboards_enabled is true — an access policy with an
# empty Principal.AWS is invalid, and on the initial bootstrap deploy no role ARNs exist in SSM yet.
resource "aws_opensearch_domain_policy" "this" {
  count       = length(local.opensearch_access_principals) > 0 ? 1 : 0
  domain_name = var.domain_name
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowConsumers"
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
