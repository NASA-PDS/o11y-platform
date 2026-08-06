# OpenSearch Module

Creates the shared OpenSearch domain for PDS observability and publishes its endpoint and ARN to SSM for downstream consumers (web-analytics, CloudFront real-time logging).

## Resources

- `aws_opensearch_domain.pds_opensearch_domain` — managed OpenSearch domain (VPC-attached when `vpc_enabled = true`)
- `aws_security_group.opensearch` — domain VPC security group; allows HTTPS inbound from the Logstash EC2 SG and the Firehose SG (created only when `vpc_enabled = true`)
- `aws_opensearch_domain_policy.domain_access_policy` — resource-based access policy granting `es:*` to the Logstash EC2 role and Firehose role (ARNs read from SSM)
- `aws_ssm_parameter.opensearch_endpoint` — publishes `https://…` endpoint to `/pds/observability/opensearch/opensearch_endpoint`
- `aws_ssm_parameter.opensearch_arn` — publishes domain ARN to `/pds/observability/opensearch/opensearch_arn`

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `domain_name` | `string` | — | OpenSearch domain name |
| `ebs_volume_gb` | `number` | — | EBS volume size per data node (GB) |
| `venue` | `string` | — | Deployment venue (`dev`, `test`, `prod`) |
| `managedby` | `string` | `pdsoperator@jpl.nasa.gov` | Tag: owner contact |
| `engine_version` | `string` | `OpenSearch_2.19` | OpenSearch engine version — pin to deployed version |
| `data_node_instance_type` | `string` | `r6g.xlarge.search` | Data node instance type |
| `data_node_count` | `number` | `3` | Number of data nodes |
| `dedicated_master_enabled` | `bool` | `true` | Enable dedicated master nodes |
| `master_node_instance_type` | `string` | `m6g.large.search` | Master node instance type |
| `master_node_count` | `number` | `3` | Number of dedicated master nodes |
| `zone_awareness_enabled` | `bool` | `false` | Multi-AZ zone awareness |
| `availability_zone_count` | `number` | `3` | AZs (must match data node count and subnet count) |
| `ebs_volume_type` | `string` | `gp3` | EBS volume type |
| `encryption_at_rest` | `bool` | `true` | Encryption at rest |
| `node_to_node_encryption` | `bool` | `true` | Node-to-node encryption |
| `vpc_enabled` | `bool` | `false` | Deploy inside VPC |
| `vpc_id` | `string` | `""` | VPC ID (required when `vpc_enabled = true`) |
| `vpc_subnet_ids` | `list(string)` | `[]` | Subnet IDs — one per AZ |
| `ec2_security_group_name` | `string` | `""` | MCP EC2 SG name (required when `vpc_enabled = true`) |
| `firehose_security_group_id` | `string` | — | Firehose delivery stream SG ID |
| `aws_region` | `string` | `us-west-2` | AWS region |
| `partition` | `string` | `aws` | AWS partition |
| `tenant` | `string` | `en` | Tag: tenant identifier |
| `component` | `string` | `observability` | Tag: component name |
| `cicd` | `string` | `terraform` | Tag: CI/CD method |

## Outputs / SSM parameters

| Name | SSM path | Description |
|---|---|---|
| `opensearch_endpoint` | `/pds/observability/opensearch/opensearch_endpoint` | HTTPS endpoint of the domain |
| `opensearch_arn` | `/pds/observability/opensearch/opensearch_arn` | ARN of the domain |
| `opensearch_domain_name` | — (Terraform output only) | Domain name |

## Deploy

```bash
cp tfvars/dev.tfvars.example tfvars/dev.tfvars
# edit tfvars/dev.tfvars — fill in vpc_id, subnet_ids, security group IDs

task opensearch:plan   VENUE=dev
task opensearch:deploy VENUE=dev
```

Domain creation takes ~15–20 minutes. Plan output is intentionally not saved with `-out` — re-run plan immediately before apply.

> **Note:** This module does not use a `common-<venue>.tfvars` file. All variables are supplied via `tfvars/<venue>.tfvars` alone.
