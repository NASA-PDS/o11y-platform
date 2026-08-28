# OpenSearch Module

Creates the shared OpenSearch domain for PDS observability and publishes its endpoint and ARN to SSM for downstream consumers (web-analytics, CloudFront real-time logging).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.58.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_opensearch_domain.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/opensearch_domain) | resource |
| [aws_opensearch_domain_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/opensearch_domain_policy) | resource |
| [aws_security_group.opensearch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_ssm_parameter.opensearch_arn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.opensearch_endpoint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.opensearch_security_group_id](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_security_group.mcp_ec2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/security_group) | data source |
| [aws_ssm_parameter.cloudfront_realtime_firehose_role_arn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |
| [aws_ssm_parameter.ec2_role_arn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Name of the managed OpenSearch domain | `string` | n/a | yes |
| <a name="input_ebs_volume_gb"></a> [ebs\_volume\_gb](#input\_ebs\_volume\_gb) | EBS volume size per data node in GB | `number` | n/a | yes |
| <a name="input_venue"></a> [venue](#input\_venue) | Tag value for venue (dev, test, prod) | `string` | n/a | yes |
| <a name="input_vpc_enabled"></a> [vpc\_enabled](#input\_vpc\_enabled) | Deploy the domain inside a VPC. This module is intended to be VPC-only. | `bool` | n/a | yes |
| <a name="input_availability_zone_count"></a> [availability\_zone\_count](#input\_availability\_zone\_count) | Number of AZs for zone awareness. Must match data\_node\_count and number of vpc\_subnet\_ids. Only used when zone\_awareness\_enabled = true. | `number` | `3` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | Effective AWS Region | `string` | `"us-west-2"` | no |
| <a name="input_cicd"></a> [cicd](#input\_cicd) | Tag value for CICD deployment method | `string` | `"terraform"` | no |
| <a name="input_component"></a> [component](#input\_component) | Tag value for component | `string` | `"observability"` | no |
| <a name="input_data_node_count"></a> [data\_node\_count](#input\_data\_node\_count) | Number of data nodes | `number` | `3` | no |
| <a name="input_data_node_instance_type"></a> [data\_node\_instance\_type](#input\_data\_node\_instance\_type) | Instance type for data nodes | `string` | `"r6g.xlarge.search"` | no |
| <a name="input_dedicated_master_enabled"></a> [dedicated\_master\_enabled](#input\_dedicated\_master\_enabled) | Enable dedicated master nodes. Recommended for prod, unnecessary for dev single-node clusters. | `bool` | `true` | no |
| <a name="input_ebs_volume_type"></a> [ebs\_volume\_type](#input\_ebs\_volume\_type) | EBS volume type | `string` | `"gp3"` | no |
| <a name="input_ec2_security_group_name"></a> [ec2\_security\_group\_name](#input\_ec2\_security\_group\_name) | Name of the MCP EC2 security group. Used to allow 443 inbound to the OpenSearch domain. Required when vpc\_enabled = true. | `string` | `""` | no |
| <a name="input_encryption_at_rest"></a> [encryption\_at\_rest](#input\_encryption\_at\_rest) | Enable encryption at rest | `bool` | `true` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | OpenSearch engine version (e.g. OpenSearch\_2.17). Pin to the deployed version to prevent unintended upgrades. | `string` | `"OpenSearch_2.19"` | no |
| <a name="input_managedby"></a> [managedby](#input\_managedby) | Tag value for owner managing the resource (e.g. PDS Team email distro) | `string` | `"pdsoperator@jpl.nasa.gov"` | no |
| <a name="input_master_node_count"></a> [master\_node\_count](#input\_master\_node\_count) | Number of dedicated master nodes | `number` | `3` | no |
| <a name="input_master_node_instance_type"></a> [master\_node\_instance\_type](#input\_master\_node\_instance\_type) | Instance type for dedicated master nodes | `string` | `"m6g.large.search"` | no |
| <a name="input_node_to_node_encryption"></a> [node\_to\_node\_encryption](#input\_node\_to\_node\_encryption) | Enable node-to-node encryption | `bool` | `true` | no |
| <a name="input_partition"></a> [partition](#input\_partition) | AWS partition (aws, aws-us-gov, aws-cn) | `string` | `"aws"` | no |
| <a name="input_realtime_monitor_enabled"></a> [realtime\_monitor\_enabled](#input\_realtime\_monitor\_enabled) | Whether the cf-realtime-monitor consumer has been deployed. When true, its Firehose role ARN is read from SSM (/pds/monitor/firehose/firehose-role-arn) and added as an OpenSearch access-policy principal. Leave false for the initial bootstrap deploy (before cf-realtime-monitor's iam module has published that parameter), then re-apply with true once it exists — this only updates the access policy, no domain redeployment. cf-realtime-monitor manages its own Firehose→OpenSearch security-group ingress rule, so no SG input is needed here. | `bool` | `false` | no |
| <a name="input_tenant"></a> [tenant](#input\_tenant) | Tag value for tenant | `string` | `"en"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID for the OpenSearch domain security group. Required when vpc\_enabled = true. | `string` | `""` | no |
| <a name="input_vpc_subnet_ids"></a> [vpc\_subnet\_ids](#input\_vpc\_subnet\_ids) | Subnet IDs for the OpenSearch domain VPC endpoint. One subnet per AZ. Required when vpc\_enabled = true. | `list(string)` | `[]` | no |
| <a name="input_web_analytics_enabled"></a> [web\_analytics\_enabled](#input\_web\_analytics\_enabled) | Whether the web-analytics consumer has been deployed. When true, its Logstash EC2 role ARN is read from SSM (/pds/web-analytics/iam/ec2\_role\_arn) and added as an OpenSearch access-policy principal. Leave false for the initial bootstrap deploy (before web-analytics' iam/policies module has published that parameter), then re-apply with true once it exists — this only updates the access policy, no domain redeployment. | `bool` | `false` | no |
| <a name="input_zone_awareness_enabled"></a> [zone\_awareness\_enabled](#input\_zone\_awareness\_enabled) | Enable zone awareness (multi-AZ). Set true for prod (3 nodes, 3 subnets), false for dev (1 node, 1 subnet). | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_opensearch_arn"></a> [opensearch\_arn](#output\_opensearch\_arn) | Managed OpenSearch domain ARN — published to /pds/observability/opensearch/opensearch\_arn |
| <a name="output_opensearch_domain_name"></a> [opensearch\_domain\_name](#output\_opensearch\_domain\_name) | Managed OpenSearch domain name (Terraform output only, not published to SSM) |
| <a name="output_opensearch_endpoint"></a> [opensearch\_endpoint](#output\_opensearch\_endpoint) | Managed OpenSearch domain endpoint URL — published to /pds/observability/opensearch/opensearch\_endpoint |
| <a name="output_opensearch_security_group_id"></a> [opensearch\_security\_group\_id](#output\_opensearch\_security\_group\_id) | OpenSearch domain VPC security group ID — published to /pds/observability/opensearch/opensearch\_security\_group\_id when vpc\_enabled |
<!-- END_TF_DOCS -->

## Deploy

```bash
cp tfvars/dev.tfvars.example tfvars/dev.tfvars
# edit tfvars/dev.tfvars — fill in vpc_id, subnet_ids, security group IDs

task opensearch:plan   VENUE=dev LOCAL=1
task opensearch:deploy VENUE=dev LOCAL=1
```

Domain creation takes ~15–20 minutes. Plan output is intentionally not saved with `-out` — re-run plan immediately before apply.

> **Note:** This module does not use a `common-<venue>.tfvars` file. All variables are supplied via `tfvars/<venue>.tfvars` alone.
