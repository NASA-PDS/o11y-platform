# Published by the opensearch module, so the domain must be applied first.
data "aws_ssm_parameter" "opensearch_arn" {
  name = "/pds/o11y-platform/opensearch/opensearch_arn"
}

locals {
  # The SSM provider marks every parameter value sensitive. A domain ARN is not a secret, and
  # hiding it would make the data_source diff unreadable in a plan.
  opensearch_arn = nonsensitive(data.aws_ssm_parameter.opensearch_arn.value)
}

# Associating the domain requires VPC access to be authorized for
# application.opensearchservice.amazonaws.com first. That authorization has no Terraform
# resource, so it is a one-time CLI step (terraform/README.md#phase-8---opensearch-ui-application).
resource "aws_opensearch_application" "this" {
  name = var.application_name

  # Application admins can edit and delete the application and create, edit, and delete
  # workspaces. IAM role ARNs belong in the groups key; the users key takes IAM user ARNs.
  app_config {
    key   = "opensearchDashboards.dashboardAdmin.groups"
    value = jsonencode(var.admin_role_arns)
  }

  data_source {
    data_source_arn         = local.opensearch_arn
    data_source_description = "PDS o11y OpenSearch domain"
  }

  tags = {
    Name = var.application_name
  }
}
