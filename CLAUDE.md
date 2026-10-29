# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`o11y-platform` is the shared observability platform for NASA Planetary Data System (PDS). It hosts infrastructure that multiple PDS sub-components consume. **All real work in this repo currently lives under `terraform/`.**

**Current components:**
- **Managed OpenSearch domain** (`terraform/opensearch/`) — VPC-only OpenSearch cluster. Both the o11y-cloudfront-batch Logstash pipeline and the o11y-cloudfront-streaming Firehose stream write to this domain. Consumers discover the endpoint via SSM.
- **OpenSearch UI Application** (`terraform/opensearch-ui/`) — the AWS-hosted UI for ops access, with the domain as its data source and IAM role ARNs as application admins. Reads the domain ARN from SSM.

**Sub-component repos that consume this platform:**
- [o11y-cloudfront-batch](https://github.com/NASA-PDS/o11y-cloudfront-batch) — Logstash EC2 ingesting node access logs
- [o11y-cloudfront-streaming](https://github.com/NASA-PDS/o11y-cloudfront-streaming) — Kinesis Firehose ingesting CloudFront real-time logs

**Shared infrastructure dependency — pdc-cds-infra:**

This repo depends on [pdc-cds-infra](https://github.com/NASA-PDS/pdc-cds-infra) (checked out at `/Users/jpadams/proj/pds/pdsen/workspace/pdc-cds-infra` locally). It is the shared infra layer for the PDS CDS ecosystem, deployed in the same AWS account and region. It owns the VPC and the CloudFront distribution (`terraform/cloudfront/pds-main/`) that later phases enable for o11y. **Do not create Cognito or built-in Dashboards resources here** — ops access is the AWS-hosted OpenSearch UI Application (`terraform/opensearch-ui/`; see `terraform/README.md#phase-8---opensearch-ui-application`). Fine-grained access control stays off.

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
│  Ops UI: OpenSearch UI Application (opensearch-ui module)                   │
│  SSM outputs: endpoint, ARN, security group ID                              │
│                (paths: terraform/README.md#ssm-contract)                    │
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
  │       ├── dev.tfvars.example   # Reference inputs for standalone Terraform only (not the operational path)
  │       ├── test.tfvars.example
  │       └── prod.tfvars.example
  ├── opensearch-ui/               # OpenSearch UI application (admins, domain data source)
  │   ├── main.tf                  # aws_opensearch_application; reads the domain ARN from SSM
  │   ├── outputs.tf               # Application ID, ARN, endpoint
  │   ├── variables.tf             # application_name, admin_role_arns
  │   ├── versions.tf
  │   ├── provider.tf
  │   └── backend.tf               # S3 backend key (pinned; bucket/region from Terragrunt)
  ├── Taskfile.yaml                # Standalone Terraform runner for opensearch:* commands (not the operational path)
  └── .taskrc.yaml                 # interactive: true (enables VENUE enum prompting)
```

There are no `backend-*.hcl` files in this repo. Real deploys get bucket/region/lock from Terragrunt in `cds-infra-deploy`. Local Task init passes the same values as `-backend-config` flags.

### Setup (first time per venue)

Primary path: set Terragrunt inputs in `cds-infra-deploy` (`venues/<venue>/o11y-platform/opensearch/terragrunt.hcl`). Leave `o11y_cloudfront_batch_enabled` / `o11y_cloudfront_streaming_enabled` false for a first deploy — see Key design decisions for the flip sequence.

Standalone Terraform (reference only; dev, test, and prod are always deployed with Terragrunt):

```bash
cd terraform/
cp opensearch/tfvars/dev.tfvars.example opensearch/tfvars/dev.tfvars
# Edit dev.tfvars (gitignored): set domain_name, vpc_id, vpc_subnet_ids
```

### Deployment commands

Primary — from a `cds-infra-deploy` checkout:

```bash
cd /path/to/cds-infra-deploy
task plan    VENUE=dev COMPONENT=o11y-platform/opensearch
task apply   VENUE=dev COMPONENT=o11y-platform/opensearch   # ~15-20 min for domain creation
task destroy VENUE=dev COMPONENT=o11y-platform/opensearch   # destroys all indexed data — irreversible
```

Standalone Terraform (this repo; reads the gitignored `opensearch/tfvars/<venue>.tfvars`; not used for operational deployments):

```bash
cd terraform/
task opensearch:init      VENUE=dev
task opensearch:validate
task opensearch:plan      VENUE=dev
task opensearch:deploy    VENUE=dev
task opensearch:endpoint
task opensearch:refresh   VENUE=dev
task opensearch:sync      VENUE=dev
task opensearch:show      VENUE=dev
task opensearch:destroy   VENUE=dev
```

`VENUE` must be one of `dev`, `test`, `prod` (enforced by Task via `.taskrc.yaml` interactive enum prompting if omitted). Run `task --list` from `terraform/` to see the full local command list.

CI (`.github/workflows/terraform_cicd.yaml`) currently only runs `terraform fmt`/`validate` on push — actual plan/apply is commented out (template default), so deploys are done via Terragrunt from `cds-infra-deploy`.

### Key design decisions

- **SSM decoupling** — the OpenSearch endpoint, domain ARN, and security group ID are published to SSM after deploy, and consumers read them at plan time; no shared Terraform state or cross-repo module references. The parameter paths, and which repos publish and read each, are in `terraform/README.md#ssm-contract`.
- **Access policy via `*_enabled` flags, not manual SSM seeding** — EC2 and Firehose role ARNs and the Logstash and Firehose security group IDs are read from SSM at plan time (paths: `terraform/README.md#ssm-contract`), but each lookup — and its entry in the access policy's `Principal.AWS` — is gated behind `o11y_cloudfront_batch_enabled` / `o11y_cloudfront_streaming_enabled` (both default `false`). This lets the domain bootstrap before either consumer exists: deploy with both false, deploy the consumers (each reads the domain's SSM outputs immediately), then flip the relevant flag to `true` and re-apply here (so `opensearch` is always applied twice) — an access-policy and ingress-rule update only, no domain redeployment. Enabling a flag before its consumer has published those SSM parameters fails the plan. `aws_opensearch_domain_policy` isn't created at all while there are no principals (both flags false and `ops_role_arns` empty). `ops_role_arns` adds operator IAM role ARNs (IAM role form, not assumed-role/STS) to the same `es:ESHttp*` statement. See `terraform/README.md#deployment-flow` for the full sequence.
- **VPC-only** — no public endpoint. OpenSearch is accessible only from within the VPC via security group rules (`aws_security_group.opensearch`, created only when `vpc_enabled = true`). Both ingress rules live in this module: the Logstash rule (gated on `o11y_cloudfront_batch_enabled && vpc_enabled`; reads the Logstash SG ID from SSM at plan time) and the Firehose rule (gated on `o11y_cloudfront_streaming_enabled && vpc_enabled`; reads the Firehose SG ID from SSM at plan time).
- **`lifecycle { ignore_changes = [tags] }`** on the OpenSearch SG — suppresses drift from AWS Config auto-tagging.
- **State** — S3 backend, key `o11y-platform/opensearch.tfstate`. Bucket/region/lock come from Terragrunt in `cds-infra-deploy`, not from `backend-*.hcl` files in this repo.
- **dev vs prod sizing** — dev uses single-node, no dedicated masters, no zone awareness (`t3.medium.search`); prod-like venues should enable `dedicated_master_enabled` and `zone_awareness_enabled` with matching subnet/AZ counts.
- **Ops access via OpenSearch UI Application** — not Cognito and not the built-in `/_dashboards` endpoint. There is no `dashboards_enabled` flag and no `cognito_options` on the domain; `advanced_security_options.enabled` stays `false`. After the domain exists, authorize `application.opensearchservice.amazonaws.com` (a one-time CLI step; the provider has no resource for it) and apply `opensearch-ui`, which creates the UI Application. Application admins are IAM role ARNs in `admin_role_arns`, written to the `opensearchDashboards.dashboardAdmin.groups` key, using the role's IAM ARN as returned by `aws iam get-role` (for SSO roles that includes the `aws-reserved/sso.amazonaws.com/` path; assumed-role/STS ARNs do not match). Admin does not grant data access; `ops_role_arns` does. See `terraform/README.md#phase-8---opensearch-ui-application`.

### Adding a new consumer

1. Have the consumer's own `iam` module publish its role ARN to an agreed SSM path (e.g. `/pds/<consumer>/iam/<role>_arn`).
2. Add a `<consumer>_enabled` bool var (default `false`) to `opensearch/variables.tf`.
3. Add a `data "aws_ssm_parameter"` block in `opensearch/main.tf`, gated with `count = var.<consumer>_enabled ? 1 : 0`.
4. Add its value to `local.opensearch_access_principals` in `opensearch/main.tf`, conditioned on the same flag.
5. If the consumer needs VPC-level access, add a gated `aws_vpc_security_group_ingress_rule` in this module (same pattern as `opensearch_https_from_firehose`: read the consumer SG ID from SSM, `count` on `<consumer>_enabled && vpc_enabled`). Do not add an inline ingress block on `aws_security_group.opensearch`.
