# OpenSearch UI Module

Creates the AWS-hosted OpenSearch UI application for ops access to the shared OpenSearch domain, with the domain as its data source and IAM roles as application admins. The domain ARN is read from SSM (`/pds/o11y-platform/opensearch/opensearch_arn`), so the `opensearch` module must be applied first.

Deployment, the one-time VPC authorization, and creating workspaces are in [Phase 8](../README.md#phase-8---opensearch-ui-application). Workspaces are created in the application and are not managed by Terraform.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.71.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_opensearch_application.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/opensearch_application) | resource |
| [aws_ssm_parameter.opensearch_arn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_admin_role_arns"></a> [admin\_role\_arns](#input\_admin\_role\_arns) | IAM role ARNs granted application admin on the OpenSearch UI application. Admins can edit and delete the application and create, edit, and delete workspaces; admin does not grant data access (see ops\_role\_arns in the opensearch module). Must be IAM role ARNs (arn:<partition>:iam::<account-id>:role/<name>), which match every session of the role; assumed-role/STS ARNs do not match. At least one is required. | `list(string)` | n/a | yes |
| <a name="input_application_name"></a> [application\_name](#input\_application\_name) | Name of the OpenSearch UI application (pds-<venue>-o11y-ui). Unique per account and Region; 3-30 characters, lowercase letters, numbers, and hyphens, starting with a letter. | `string` | n/a | yes |
| <a name="input_managedby"></a> [managedby](#input\_managedby) | Tag value for owner managing the resource (e.g. PDS Team email distro) | `string` | n/a | yes |
| <a name="input_venue"></a> [venue](#input\_venue) | Tag value for venue (dev, test, prod) | `string` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | Effective AWS Region | `string` | `"us-west-2"` | no |
| <a name="input_cicd"></a> [cicd](#input\_cicd) | Tag value for CICD deployment method | `string` | `"iac"` | no |
| <a name="input_component"></a> [component](#input\_component) | Tag value for component | `string` | `"o11y-platform"` | no |
| <a name="input_tenant"></a> [tenant](#input\_tenant) | Tag value for tenant | `string` | `"en"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_application_arn"></a> [application\_arn](#output\_application\_arn) | OpenSearch UI application ARN |
| <a name="output_application_endpoint"></a> [application\_endpoint](#output\_application\_endpoint) | OpenSearch UI application URL |
| <a name="output_application_id"></a> [application\_id](#output\_application\_id) | OpenSearch UI application ID |
<!-- END_TF_DOCS -->
