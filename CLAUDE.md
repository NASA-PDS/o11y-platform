# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`o11y-platform` is the shared observability platform for NASA Planetary Data System (PDS). It hosts infrastructure that multiple PDS sub-components consume. **All real work in this repo currently lives under `terraform/`.**

**Current components:**
- **Managed OpenSearch domain** (`terraform/opensearch/`) — VPC-only OpenSearch cluster. Both the o11y-cloudfront-batch Logstash pipeline and the o11y-cloudfront-streaming Firehose stream write to this domain. Consumers discover the endpoint via SSM.

**Sub-component repos that consume this platform:**
- [o11y-cloudfront-batch](https://github.com/NASA-PDS/o11y-cloudfront-batch) — Logstash EC2 ingesting node access logs
- [o11y-cloudfront-streaming](https://github.com/NASA-PDS/o11y-cloudfront-streaming) — Kinesis Firehose ingesting CloudFront real-time logs

**Shared infrastructure dependency — pdc-cds-infra:**

This repo depends on [pdc-cds-infra](https://github.com/NASA-PDS/pdc-cds-infra) (checked out at `/Users/jpadams/proj/pds/pdsen/workspace/pdc-cds-infra` locally). It is the shared infra layer for the PDS CDS ecosystem, deployed in the same AWS account and region. It owns the VPC and the CloudFront distribution (`terraform/cloudfront/pds-main/`) that later phases enable for o11y. **Do not create Cognito or Dashboards resources here** — ops access is the AWS-hosted OpenSearch UI Application (manual; see `terraform/README.md#opensearch-ui-application`). Fine-grained access control stays off.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          pdc-cds-infra                                      │
│  VPC + CloudFront (pds-main, enabled in a later phase)                      │
└──────────────────────────────────┬──────────────────────────────────────────┘
                                   │ same account / VPC
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          o11y-platform (this repo)                          │
│  OpenSearch domain (VPC-only)                                               │
│  Ingress: EC2 (always) + Firehose (if o11y_cloudfront_streaming_enabled)    │
│  Ops UI: OpenSearch UI Application (manual, not Terraform)                  │
│  SSM outputs: /pds/o11y-platform/opensearch/opensearch_endpoint             │
│               /pds/o11y-platform/opensearch/opensearch_arn                  │
│               /pds/o11y-platform/opensearch/opensearch_security_group_id    │
└────────────┬──────────────────────────────┬────────────────────────────────┘
             │ reads endpoint/ARN via SSM   │ this module reads Firehose
             ▼                              │ role ARN + SG ID when enabled
┌────────────────────────┐    ┌─────────────┴───────────────┐
│  o11y-cloudfront-batch │    │  o11y-cloudfront-streaming  │
│  Logstash EC2          │    │  Kinesis Firehose           │
│  (writes logs)         │    │  (writes logs)              │
└────────────────────────┘    └─────────────────────────────┘
```

> **Note:** `src/`, `tests/`, `pyproject.toml`, `setup.cfg`, `tox.ini`, and `.pre-commit-config.yaml` are unmodified boilerplate from the [pds-template-repo-python](https://github.com/NASA-PDS/pds-template-repo-python) (package still named `your_package_name`). There is no real Python code in this repo — don't treat that scaffolding as part of the actual project.

## Terraform

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.10.0
- [Terragrunt](https://terragrunt.gruntwork.io/docs/getting-started/install/) >= 0.55
- [Task](https://taskfile.dev) — `brew install go-task/tap/go-task`
- A local checkout of `cds-infra-deploy` — venue inputs live there as `venues/<venue>/o11y-platform/opensearch/terragrunt.hcl`
- AWS credentials exported to the shell (S3 backend requires `AWS_PROFILE` to be unset):
  ```bash
  eval $(aws configure export-credentials --profile <your-profile> --format env)
  unset AWS_PROFILE
  ```

### Structure

```
terraform/
  ├── opensearch/                  # OpenSearch domain (shared platform)
  │   ├── main.tf                  # Domain, SGs, access policy
  │   ├── outputs.tf               # Publishes endpoint + ARN + security group ID to SSM
  │   ├── variables.tf
  │   ├── versions.tf              # required_version, aws provider ~> 6.0
  │   ├── provider.tf              # default_tags: tenant/venue/component/managedby/cicd
  │   ├── backend.tf               # S3 backend key (pinned; bucket/region from Terragrunt)
  │   └── tfvars/
  │       ├── dev.tfvars.example   # Template — copy to <venue>.tfvars (gitignored) for LOCAL=1
  │       ├── test.tfvars.example
  │       └── prod.tfvars.example
  ├── Taskfile.yaml                # Local fallback runner for opensearch:* commands
  └── .taskrc.yaml                 # interactive: true (enables VENUE enum prompting)
```

There are no `backend-*.hcl` files in this repo. Real deploys get bucket/region/lock from Terragrunt in `cds-infra-deploy`. Local Task init passes the same values as `-backend-config` flags.

### Setup (first time per venue)

Primary path: set Terragrunt inputs in `cds-infra-deploy` (`venues/<venue>/o11y-platform/opensearch/terragrunt.hcl`). Leave `o11y_cloudfront_batch_enabled` / `o11y_cloudfront_streaming_enabled` false for a first deploy — see Key design decisions for the flip sequence.

Local Task fallback (iteration only):

```bash
cd terraform/
cp opensearch/tfvars/dev.tfvars.example opensearch/tfvars/dev.tfvars
# Edit dev.tfvars: set domain_name, vpc_id, vpc_subnet_ids, ec2_security_group_name
```

### Deployment commands

Primary — from a `cds-infra-deploy` checkout:

```bash
cd /path/to/cds-infra-deploy
task plan    VENUE=dev COMPONENT=o11y-platform/opensearch
task apply   VENUE=dev COMPONENT=o11y-platform/opensearch   # ~15-20 min for domain creation
task destroy VENUE=dev COMPONENT=o11y-platform/opensearch   # destroys all indexed data — irreversible
```

Local Task fallback (this repo; `LOCAL=1` uses gitignored tfvars):

```bash
cd terraform/
task opensearch:init      VENUE=dev LOCAL=1
task opensearch:validate
task opensearch:plan      VENUE=dev LOCAL=1
task opensearch:deploy    VENUE=dev LOCAL=1
task opensearch:endpoint
task opensearch:refresh   VENUE=dev LOCAL=1
task opensearch:sync      VENUE=dev LOCAL=1
task opensearch:show      VENUE=dev
task opensearch:destroy   VENUE=dev LOCAL=1
```

`VENUE` must be one of `dev`, `test`, `prod` (enforced by Task via `.taskrc.yaml` interactive enum prompting if omitted). Run `task --list` from `terraform/` to see the full local command list.

CI (`.github/workflows/terraform_cicd.yaml`) currently only runs `terraform fmt`/`validate` on push — actual plan/apply is commented out (template default), so deploys are done via Terragrunt from `cds-infra-deploy`.

### Key design decisions

- **SSM decoupling** — the OpenSearch endpoint, domain ARN, and security group ID are published to `/pds/o11y-platform/opensearch/opensearch_endpoint`, `/pds/o11y-platform/opensearch/opensearch_arn`, and `/pds/o11y-platform/opensearch/opensearch_security_group_id` after deploy. Consumers read these at plan time (the ARN is consumed by o11y-cloudfront-batch's `iam/policies` module to scope IAM permissions); no shared Terraform state or cross-repo module references.
- **Access policy via `*_enabled` flags, not manual SSM seeding** — EC2 and Firehose role ARNs are read from SSM at plan time (`/pds/o11y-cloudfront-batch/iam/ec2_role_arn`, `/pds/o11y-cloudfront-streaming/firehose/firehose-role-arn`), but each lookup — and its entry in the access policy's `Principal.AWS` — is gated behind `o11y_cloudfront_batch_enabled` / `o11y_cloudfront_streaming_enabled` (both default `false`). This lets the domain bootstrap before either consumer exists: deploy with both false, deploy the consumers (each reads the domain's SSM outputs immediately), then flip the relevant flag to `true` and re-apply here — an access-policy-only update, no domain redeployment. `aws_opensearch_domain_policy` isn't created at all while both flags are false. See `terraform/README.md#deployment-flow` for the full sequence.
- **VPC-only** — no public endpoint. OpenSearch is accessible only from within the VPC via security group rules (`aws_security_group.opensearch`, created only when `vpc_enabled = true`). Both ingress rules live in this module: the EC2 rule (unconditional; MCP EC2 SG is pre-existing shared infra) and the Firehose rule (gated on `o11y_cloudfront_streaming_enabled && vpc_enabled`; reads the Firehose SG ID from SSM at plan time).
- **`lifecycle { ignore_changes = [tags] }`** on the OpenSearch SG — suppresses drift from AWS Config auto-tagging.
- **State** — S3 backend, key `o11y-platform/opensearch.tfstate`. Bucket/region/lock come from Terragrunt in `cds-infra-deploy`, not from `backend-*.hcl` files in this repo.
- **dev vs prod sizing** — dev uses single-node, no dedicated masters, no zone awareness (`t3.medium.search`); prod-like venues should enable `dedicated_master_enabled` and `zone_awareness_enabled` with matching subnet/AZ counts.
- **Ops access via OpenSearch UI Application** — not Cognito and not the built-in `/_dashboards` endpoint. There is no `dashboards_enabled` flag and no `cognito_options` on the domain; `advanced_security_options.enabled` stays `false`. After the domain exists, authorize `application.opensearchservice.amazonaws.com` and create the UI Application in the console. See `terraform/README.md#opensearch-ui-application`.

### Adding a new consumer

1. Have the consumer's own `iam` module publish its role ARN to an agreed SSM path (e.g. `/pds/<consumer>/iam/<role>_arn`).
2. Add a `<consumer>_enabled` bool var (default `false`) to `opensearch/variables.tf`.
3. Add a `data "aws_ssm_parameter"` block in `opensearch/main.tf`, gated with `count = var.<consumer>_enabled ? 1 : 0`.
4. Add its value to `local.opensearch_access_principals` in `opensearch/main.tf`, conditioned on the same flag.
5. If the consumer needs VPC-level access, add a gated `aws_vpc_security_group_ingress_rule` in this module (same pattern as `opensearch_https_from_firehose`: read the consumer SG ID from SSM, `count` on `<consumer>_enabled && vpc_enabled`). Do not add an inline ingress block on `aws_security_group.opensearch`.
