# OpenSearch Module

Creates the shared OpenSearch domain for PDS observability and publishes its endpoint, ARN, and (when vpc_enabled = true) security group ID to SSM for downstream consumers (o11y-cloudfront-batch, o11y-cloudfront-streaming).

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
| [aws_vpc_security_group_ingress_rule.opensearch_https_from_firehose](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.opensearch_https_from_logstash](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_ssm_parameter.ec2_role_arn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |
| [aws_ssm_parameter.firehose_role_arn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |
| [aws_ssm_parameter.firehose_security_group_id](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |
| [aws_ssm_parameter.logstash_security_group_id](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Name of the managed OpenSearch domain | `string` | n/a | yes |
| <a name="input_ebs_volume_gb"></a> [ebs\_volume\_gb](#input\_ebs\_volume\_gb) | EBS volume size per data node in GB | `number` | n/a | yes |
| <a name="input_managedby"></a> [managedby](#input\_managedby) | Tag value for owner managing the resource (e.g. PDS Team email distro) | `string` | n/a | yes |
| <a name="input_venue"></a> [venue](#input\_venue) | Tag value for venue (dev, test, prod) | `string` | n/a | yes |
| <a name="input_vpc_enabled"></a> [vpc\_enabled](#input\_vpc\_enabled) | Deploy the domain inside a VPC. This module is intended to be VPC-only. | `bool` | n/a | yes |
| <a name="input_availability_zone_count"></a> [availability\_zone\_count](#input\_availability\_zone\_count) | Number of AZs for zone awareness. Must match data\_node\_count and number of vpc\_subnet\_ids. Only used when zone\_awareness\_enabled = true. | `number` | `3` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | Effective AWS Region | `string` | `"us-west-2"` | no |
| <a name="input_cicd"></a> [cicd](#input\_cicd) | Tag value for CICD deployment method | `string` | `"iac"` | no |
| <a name="input_component"></a> [component](#input\_component) | Tag value for component | `string` | `"o11y-platform"` | no |
| <a name="input_data_node_count"></a> [data\_node\_count](#input\_data\_node\_count) | Number of data nodes | `number` | `3` | no |
| <a name="input_data_node_instance_type"></a> [data\_node\_instance\_type](#input\_data\_node\_instance\_type) | Instance type for data nodes | `string` | `"r6g.xlarge.search"` | no |
| <a name="input_dedicated_master_enabled"></a> [dedicated\_master\_enabled](#input\_dedicated\_master\_enabled) | Enable dedicated master nodes. Recommended for prod, unnecessary for dev single-node clusters. | `bool` | `true` | no |
| <a name="input_ebs_volume_type"></a> [ebs\_volume\_type](#input\_ebs\_volume\_type) | EBS volume type | `string` | `"gp3"` | no |
| <a name="input_encryption_at_rest"></a> [encryption\_at\_rest](#input\_encryption\_at\_rest) | Enable encryption at rest | `bool` | `true` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | OpenSearch engine version (e.g. OpenSearch\_2.17). Pin to the deployed version to prevent unintended upgrades. | `string` | `"OpenSearch_2.19"` | no |
| <a name="input_master_node_count"></a> [master\_node\_count](#input\_master\_node\_count) | Number of dedicated master nodes | `number` | `3` | no |
| <a name="input_master_node_instance_type"></a> [master\_node\_instance\_type](#input\_master\_node\_instance\_type) | Instance type for dedicated master nodes | `string` | `"m6g.large.search"` | no |
| <a name="input_node_to_node_encryption"></a> [node\_to\_node\_encryption](#input\_node\_to\_node\_encryption) | Enable node-to-node encryption | `bool` | `true` | no |
| <a name="input_o11y_cloudfront_batch_enabled"></a> [o11y\_cloudfront\_batch\_enabled](#input\_o11y\_cloudfront\_batch\_enabled) | Whether the o11y-cloudfront-batch consumer has been deployed. When true, its Logstash EC2 role ARN is read from SSM (/pds/o11y-cloudfront-batch/iam/roles/ec2/instance-role-arn) and added as an OpenSearch access-policy principal, and its Logstash SG ID is read from SSM (/pds/o11y-cloudfront-batch/ec2/logstash\_security\_group\_id) to create the Logstash→OpenSearch VPC ingress rule. Leave false for the initial bootstrap deploy (before o11y-cloudfront-batch's iam and logstash modules have published those parameters), then re-apply with true once both exist — this only updates the access policy and ingress rule, no domain redeployment. | `bool` | `false` | no |
| <a name="input_o11y_cloudfront_streaming_enabled"></a> [o11y\_cloudfront\_streaming\_enabled](#input\_o11y\_cloudfront\_streaming\_enabled) | Whether the o11y-cloudfront-streaming consumer has been deployed. When true, its Firehose role ARN is read from SSM (/pds/o11y-cloudfront-streaming/firehose/firehose-role-arn) and added as an OpenSearch access-policy principal, and its Firehose SG ID is read from SSM (/pds/o11y-cloudfront-streaming/firehose/firehose-security-group-id) to create the Firehose→OpenSearch VPC ingress rule. Leave false for the initial bootstrap deploy (before o11y-cloudfront-streaming has published those SSM parameters), then re-apply with true once it exists — this only updates the access policy and ingress rule, no domain redeployment. | `bool` | `false` | no |
| <a name="input_ops_role_arns"></a> [ops\_role\_arns](#input\_ops\_role\_arns) | IAM role ARNs of operators granted es:ESHttp* on the domain, in addition to the enabled consumer roles. Used for ops access through the OpenSearch UI Application. Must be IAM role ARNs (arn:<partition>:iam::<account-id>:role/<name>), which match every session of the role; assumed-role/STS ARNs do not match. Leave empty when operators already have es:ESHttp* through their own IAM policy. | `list(string)` | `[]` | no |
| <a name="input_partition"></a> [partition](#input\_partition) | AWS partition (aws, aws-us-gov, aws-cn) | `string` | `"aws"` | no |
| <a name="input_tenant"></a> [tenant](#input\_tenant) | Tag value for tenant | `string` | `"en"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID for the OpenSearch domain security group. Required when vpc\_enabled = true. | `string` | `""` | no |
| <a name="input_vpc_subnet_ids"></a> [vpc\_subnet\_ids](#input\_vpc\_subnet\_ids) | Subnet IDs for the OpenSearch domain VPC endpoint. One subnet per AZ. Required when vpc\_enabled = true. | `list(string)` | `[]` | no |
| <a name="input_zone_awareness_enabled"></a> [zone\_awareness\_enabled](#input\_zone\_awareness\_enabled) | Enable zone awareness (multi-AZ). Set true for prod (3 nodes, 3 subnets), false for dev (1 node, 1 subnet). | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_opensearch_arn"></a> [opensearch\_arn](#output\_opensearch\_arn) | Managed OpenSearch domain ARN — published to /pds/o11y-platform/opensearch/opensearch\_arn |
| <a name="output_opensearch_domain_name"></a> [opensearch\_domain\_name](#output\_opensearch\_domain\_name) | Managed OpenSearch domain name (Terraform output only, not published to SSM) |
| <a name="output_opensearch_endpoint"></a> [opensearch\_endpoint](#output\_opensearch\_endpoint) | Managed OpenSearch domain endpoint URL — published to /pds/o11y-platform/opensearch/opensearch\_endpoint |
| <a name="output_opensearch_security_group_id"></a> [opensearch\_security\_group\_id](#output\_opensearch\_security\_group\_id) | OpenSearch domain VPC security group ID — published to /pds/o11y-platform/opensearch/opensearch\_security\_group\_id when vpc\_enabled |
<!-- END_TF_DOCS -->

## Deploy

### Operational deployments (Terragrunt via cds-infra-deploy)

Every venue (dev, test, prod) is deployed this way. All inputs live in
`venues/<venue>/o11y-platform/opensearch/terragrunt.hcl` in `cds-infra-deploy`; there are no
tfvars files in the operational path. The inputs block looks like this (placeholder values only):

```hcl
inputs = {
  aws_region = "<region>"
  tenant     = "<tenant>"
  component  = "o11y-platform"
  managedby  = "<team-email>"
  venue      = "<dev|test|prod>"

  domain_name   = "<domain-name>"
  ebs_volume_gb = 100

  data_node_instance_type   = "<instance-type>"
  data_node_count           = 1
  master_node_instance_type = "<instance-type>"
  master_node_count         = 3
  dedicated_master_enabled  = false
  zone_awareness_enabled    = false

  vpc_enabled    = true
  vpc_id         = "<vpc-id>"
  vpc_subnet_ids = ["<private-subnet-id>"]

  # Bootstrap with both false; set to true on the second apply, after the consumer's
  # modules have published their SSM parameters (see ../README.md#deployment-flow).
  o11y_cloudfront_batch_enabled     = false
  o11y_cloudfront_streaming_enabled = false

  # Operator IAM role ARNs granted es:ESHttp* on the domain (see ../README.md#phase-8---opensearch-ui-application).
  ops_role_arns = []

  engine_version = "OpenSearch_2.19"
}
```

Deploy it from the runbook. The bootstrap apply is [Phase 1](../README.md#phase-1---bootstrap-opensearch) and the consumer re-apply is [Phase 5](../README.md#phase-5---grant-consumers-opensearch-access). Each phase's Setup block assigns the variables, exports the credentials, and changes into the `cds-infra-deploy` checkout.

### Standalone Terraform (reference only, not the operational path)

The `tfvars/*.tfvars.example` files are a reference for the inputs the module takes when it is
run as plain Terraform, outside Terragrunt. They are not how dev, test, or prod are deployed
and are not kept in step with the venue values in `cds-infra-deploy`. Use them to try the module
in a scratch account, or as a checklist of the inputs a Terragrunt `inputs` block needs.

```bash
PROFILE_NAME="<sso-profile>"
O11Y_PLATFORM_DIR="<path-to-o11y-platform-checkout>"

# The Terraform S3 backend needs exported credentials with AWS_PROFILE unset.
eval $(aws configure export-credentials --profile "${PROFILE_NAME}" --format env)
unset AWS_PROFILE

cd "${O11Y_PLATFORM_DIR}/terraform"
cp opensearch/tfvars/dev.tfvars.example opensearch/tfvars/dev.tfvars
# edit dev.tfvars (gitignored): fill in domain_name, vpc_id, vpc_subnet_ids

task opensearch:plan   VENUE=dev
task opensearch:deploy VENUE=dev
```

### Post-deploy and verification

- **Console access for the VPC domain** (one-time authorization of `application.opensearchservice.amazonaws.com`): [Phase 8, Step 1](../README.md#phase-8---opensearch-ui-application).
- **Smoke test** (`scripts/smoke-test.sh` at the repo root): [Phase 1 Verify](../README.md#phase-1---bootstrap-opensearch).

## Upgrade

Re-apply from `cds-infra-deploy` after changing the Terragrunt inputs. Run the [smoke test](../README.md#phase-1---bootstrap-opensearch) afterward.

### Engine version

Update `engine_version` in the Terragrunt inputs (e.g. `"OpenSearch_2.19"` → next version) and re-apply. AWS performs a blue/green upgrade — the domain stays up but enters "Processing" state for ~30 minutes. No downtime for consumers. Always pin the version explicitly; do not rely on the module default, which tracks the latest tested version.

### Node count or instance type

Update `data_node_count`, `data_node_instance_type`, or `master_node_instance_type` and re-apply. For single-node dev clusters scaling to multi-node, also set `zone_awareness_enabled = true` and provide multiple `vpc_subnet_ids` (one per AZ) — this triggers a domain configuration update (~10 min), not a replacement.
