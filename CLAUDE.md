# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`pdc-observability` is the shared observability platform for NASA Planetary Data System (PDS). It hosts infrastructure that multiple PDS sub-components consume.

**Current components:**
- **Managed OpenSearch domain** (`terraform/opensearch_managed/`) — VPC-only OpenSearch cluster. Both the web-analytics Logstash pipeline and the CloudFront realtime-monitor Firehose stream write to this domain. Consumers discover the endpoint via SSM.

**Sub-component repos that consume this platform:**
- [web-analytics](https://github.com/NASA-PDS/web-analytics) — Logstash EC2 ingesting node access logs
- [cloudfront-realtime-monitor](https://github.com/NASA-PDS/cloudfront-realtime-monitor) — Kinesis Firehose ingesting CloudFront real-time logs

## Terraform

### Structure

```
terraform/
  ├── opensearch_managed/         # OpenSearch domain (shared platform)
  │   ├── main.tf                 # Domain, SGs, access policy
  │   ├── outputs.tf              # Publishes endpoint to SSM
  │   ├── variables.tf
  │   ├── versions.tf
  │   ├── provider.tf
  │   ├── backend.tf              # S3 backend key
  │   ├── backend-dev.hcl         # Venue-specific backend config (bucket, region)
  │   ├── backend-prod.hcl
  │   └── tfvars/
  │       ├── dev.tfvars.example  # Template — copy to dev.tfvars (gitignored)
  │       └── dev.tfvars          # gitignored — VPC IDs, SG names/IDs
  ├── Taskfile.yaml               # Task runner for opensearch:* commands
  └── .taskrc.yaml                # interactive: true (enables VENUE enum prompting)
```

### Deployment commands

```bash
cd terraform/

task opensearch:init    VENUE=dev
task opensearch:plan    VENUE=dev
task opensearch:deploy  VENUE=dev
task opensearch:endpoint VENUE=dev   # confirm SSM output
```

All other deployment commands (`task --list` to see the full list).

### Key design decisions

- **SSM decoupling** — the OpenSearch endpoint is published to `/pds/observability/opensearch_managed/opensearch_endpoint` after deploy. Consumers read this at plan time; no shared Terraform state or cross-repo module references.
- **Access policy via SSM** — EC2 and Firehose role ARNs are read from SSM at plan time (`/pds/web-analytics/iam/ec2_role_arn`, `/pds/monitor/firehose/firehose-role-arn`). No role names in tfvars.
- **VPC-only** — no public endpoint. OpenSearch is accessible only from within the VPC via security group rules.
- **`lifecycle { ignore_changes = [tags] }`** on the OpenSearch SG — suppresses drift from AWS Config auto-tagging.

### Adding a new consumer

1. Obtain the consumer's IAM role ARN.
2. Publish it to an agreed SSM path (e.g. `/pds/<consumer>/iam/<role>_arn`).
3. Add a `data "aws_ssm_parameter"` block in `opensearch_managed/main.tf`.
4. Add the ARN to the `AllowEC2AndFirehose` principal list in the access policy.
5. Add a SG ingress rule if the consumer needs VPC-level access.
