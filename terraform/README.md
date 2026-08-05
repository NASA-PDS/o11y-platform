# PDS Observability — Terraform

Deploys the shared observability infrastructure for the NASA Planetary Data System:

- **Managed OpenSearch domain** — VPC-only, IAM resource-based access control, ECS v8 index schema

Consumers connect via SSM — no direct Terraform dependencies required:

| Consumer | SSM key read |
|---|---|
| [web-analytics](https://github.com/NASA-PDS/web-analytics) — Logstash EC2 | `/pds/observability/opensearch_managed/opensearch_endpoint` |
| [cloudfront-realtime-monitor](https://github.com/NASA-PDS/cloudfront-realtime-monitor) — Kinesis Firehose | `/pds/observability/opensearch_managed/opensearch_endpoint` |

```
terraform/
  └── opensearch_managed/   # Shared OpenSearch domain — 🔑 Power-User
```

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.0
- [Task](https://taskfile.dev) — `brew install go-task/tap/go-task`
- AWS credentials exported:
  ```bash
  eval $(aws configure export-credentials --profile <your-profile> --format env)
  unset AWS_PROFILE  # required for Terraform S3 backend compatibility
  ```

---

## Setup

All tfvars are gitignored. Copy the example and fill in values:

```bash
cd terraform/

cp opensearch_managed/tfvars/dev.tfvars.example opensearch_managed/tfvars/dev.tfvars
# Edit dev.tfvars: set vpc_id, vpc_subnet_ids, ec2_security_group_name, firehose_security_group_id
```

Key values to fill in:

| File | Variable | Notes |
|---|---|---|
| `opensearch_managed/tfvars/dev.tfvars` | `vpc_id`, `vpc_subnet_ids` | VPC where OpenSearch endpoint is placed |
| `opensearch_managed/tfvars/dev.tfvars` | `ec2_security_group_name` | MCP EC2 SG — allows Logstash HTTPS inbound |
| `opensearch_managed/tfvars/dev.tfvars` | `firehose_security_group_id` | CloudFront Firehose SG — allows Firehose HTTPS inbound |

---

## Deployment

### OpenSearch domain — 🔑 Power-User (~15-20 min)

```bash
cd terraform/

task opensearch:init    VENUE=dev
task opensearch:plan    VENUE=dev
task opensearch:deploy  VENUE=dev
task opensearch:endpoint VENUE=dev   # confirm endpoint stored in SSM
```

After deploy, the endpoint is published to SSM automatically:
```
/pds/observability/opensearch_managed/opensearch_endpoint
```

Consumers read this value at plan time — no manual coordination needed.

---

## Access control

OpenSearch access is IAM resource-based (no FGAC). Two principals are granted `es:*`:

| Principal ARN | Source |
|---|---|
| EC2 role ARN | SSM `/pds/web-analytics/iam/ec2_role_arn` (published by web-analytics logstash deploy) |
| Firehose role ARN | SSM `/pds/monitor/firehose/firehose-role-arn` (published by cloudfront-realtime-monitor) |

Both values are read from SSM at plan time. If either SSM parameter doesn't exist yet, seed it manually before planning:

```bash
# Seed EC2 role ARN (if logstash hasn't been deployed yet)
aws ssm put-parameter \
  --name /pds/web-analytics/iam/ec2_role_arn \
  --type String \
  --value "arn:aws:iam::<account-id>:role/<ec2-role-name>" \
  --overwrite

# Seed Firehose role ARN (if realtime-monitor hasn't been deployed yet)
aws ssm put-parameter \
  --name /pds/monitor/firehose/firehose-role-arn \
  --type String \
  --value "arn:aws:iam::<account-id>:role/service-role/<firehose-role-name>" \
  --overwrite
```

---

## Teardown

```bash
task opensearch:destroy VENUE=dev   # destroys all indexed data — irreversible
```

---

## Architecture notes

- **State file** stored in S3 (`pds-<venue>-<cicd>-infra`):
  - `web-analytics/opensearch.tfstate` — OpenSearch domain (key kept for state continuity)
- **VPC/SG values** are in tfvars. TODO: source EC2 SG from SSM under `/pds/cds-infra/vpc/security_groups/` once MCP publishes it.
- **OpenSearch access policy** — principals sourced from SSM at plan time. No role names in tfvars.
- **Adding a new consumer** — grant its role ARN `es:*` access by adding a new SSM parameter and extending the `AllowEC2AndFirehose` principal list in `opensearch_managed/main.tf`.
