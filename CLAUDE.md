# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`pdc-observability` is the shared observability platform for NASA Planetary Data System (PDS). It hosts infrastructure that multiple PDS sub-components consume. **All real work in this repo currently lives under `terraform/`.**

**Current components:**
- **Managed OpenSearch domain** (`terraform/opensearch/`) — VPC-only OpenSearch cluster. Both the web-analytics Logstash pipeline and the CloudFront realtime-monitor Firehose stream write to this domain. Consumers discover the endpoint via SSM.

**Sub-component repos that consume this platform:**
- [web-analytics](https://github.com/NASA-PDS/web-analytics) — Logstash EC2 ingesting node access logs
- [cf-realtime-monitor](https://github.com/NASA-PDS/cf-realtime-monitor) — Kinesis Firehose ingesting CloudFront real-time logs

> **Note:** `src/`, `tests/`, `pyproject.toml`, `setup.cfg`, `tox.ini`, and `.pre-commit-config.yaml` are unmodified boilerplate from the [pds-template-repo-python](https://github.com/NASA-PDS/pds-template-repo-python) (package still named `your_package_name`). There is no real Python code in this repo — don't treat that scaffolding as part of the actual project.

## Terraform

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.10.0
- [Task](https://taskfile.dev) — `brew install go-task/tap/go-task`
- AWS credentials exported to the shell (S3 backend requires `AWS_PROFILE` to be unset):
  ```bash
  eval $(aws configure export-credentials --profile <your-profile> --format env)
  unset AWS_PROFILE
  ```

### Structure

```
terraform/
  ├── opensearch/                 # OpenSearch domain (shared platform)
  │   ├── main.tf                 # Domain, SGs, access policy
  │   ├── outputs.tf              # Publishes endpoint + ARN + security group ID to SSM
  │   ├── variables.tf
  │   ├── versions.tf              # required_version, aws provider ~> 6.0
  │   ├── provider.tf              # default_tags: tenant/venue/component/managedby/cicd
  │   ├── backend.tf               # S3 backend key (pinned; bucket/region come from backend-<venue>.hcl)
  │   ├── backend-dev.hcl          # Venue-specific backend config (bucket, region)
  │   ├── backend-prod.hcl
  │   └── tfvars/
  │       ├── dev.tfvars.example   # Template — copy to dev.tfvars (gitignored)
  │       ├── dev.tfvars           # gitignored — VPC IDs, SG names/IDs
  │       └── prod.tfvars          # gitignored
  ├── Taskfile.yaml                # Task runner for opensearch:* commands
  └── .taskrc.yaml                 # interactive: true (enables VENUE enum prompting)
```

### Setup (first time per venue)

```bash
cd terraform/
cp opensearch/tfvars/dev.tfvars.example opensearch/tfvars/dev.tfvars
# Edit dev.tfvars: set domain_name, vpc_id, vpc_subnet_ids, ec2_security_group_name
# Leave web_analytics_enabled / realtime_monitor_enabled at their default (false) for a first deploy
```

### Deployment commands

```bash
cd terraform/

task opensearch:init      VENUE=dev            # terraform init -backend-config=backend-<venue>.hcl
task opensearch:validate                        # terraform validate
task opensearch:plan      VENUE=dev
task opensearch:deploy    VENUE=dev             # apply — slow, ~15-20 min for domain creation
task opensearch:endpoint  VENUE=dev             # confirm SSM output
task opensearch:refresh   VENUE=dev             # plan -refresh-only
task opensearch:sync      VENUE=dev             # apply -refresh-only
task opensearch:show      VENUE=dev
task opensearch:destroy   VENUE=dev             # destroys all indexed data — irreversible
```

`VENUE` must be one of `dev`, `test`, `prod` (enforced by Task via `.taskrc.yaml` interactive enum prompting if omitted). Run `task --list` from `terraform/` to see the full command list.

CI (`.github/workflows/terraform_cicd.yaml`) currently only runs `terraform fmt`/`validate` on push — actual plan/apply is commented out (template default), so deploys are done manually via the Task commands above.

### Key design decisions

- **SSM decoupling** — the OpenSearch endpoint, domain ARN, and security group ID are published to `/pds/observability/opensearch/opensearch_endpoint`, `/pds/observability/opensearch/opensearch_arn`, and `/pds/observability/opensearch/opensearch_security_group_id` after deploy. Consumers read these at plan time (the ARN is consumed by web-analytics' `iam/policies` module to scope IAM permissions; the SG ID by cf-realtime-monitor, which manages its own ingress rule against it); no shared Terraform state or cross-repo module references.
- **Access policy via `*_enabled` flags, not manual SSM seeding** — EC2 and Firehose role ARNs are read from SSM at plan time (`/pds/web-analytics/iam/ec2_role_arn`, `/pds/monitor/firehose/firehose-role-arn`), but each lookup — and its entry in the access policy's `Principal.AWS` — is gated behind `web_analytics_enabled` / `realtime_monitor_enabled` (both default `false`). This lets the domain bootstrap before either consumer exists: deploy with both false, deploy the consumers (each reads the domain's SSM outputs immediately), then flip the relevant flag to `true` and re-apply here — an access-policy-only update, no domain redeployment. `aws_opensearch_domain_policy` isn't created at all while both flags are false. See `terraform/README.md#deployment-flow` for the full sequence.
- **VPC-only** — no public endpoint. OpenSearch is accessible only from within the VPC via security group rules (`aws_security_group.opensearch`, created only when `vpc_enabled = true`). The EC2 ingress rule lives on this SG (the MCP EC2 SG is pre-existing shared infra); the Firehose ingress rule does not — cf-realtime-monitor creates it directly against this SG's ID (read from SSM).
- **`lifecycle { ignore_changes = [tags] }`** on the OpenSearch SG — suppresses drift from AWS Config auto-tagging.
- **State** — S3 backend, key `observability/opensearch.tfstate`, bucket/region per-venue in `backend-<venue>.hcl`.
- **dev vs prod sizing** — dev uses single-node, no dedicated masters, no zone awareness (`t3.medium.search`); prod-like venues should enable `dedicated_master_enabled` and `zone_awareness_enabled` with matching subnet/AZ counts.

### Adding a new consumer

1. Have the consumer's own `iam` module publish its role ARN to an agreed SSM path (e.g. `/pds/<consumer>/iam/<role>_arn`).
2. Add a `<consumer>_enabled` bool var (default `false`) to `opensearch/variables.tf`.
3. Add a `data "aws_ssm_parameter"` block in `opensearch/main.tf`, gated with `count = var.<consumer>_enabled ? 1 : 0`.
4. Add its value to `local.opensearch_access_principals` in `opensearch/main.tf`, conditioned on the same flag.
5. If the consumer needs VPC-level access, have it manage its own `aws_vpc_security_group_ingress_rule` against this domain's SG ID (read from the `opensearch_security_group_id` SSM output) rather than adding an inline ingress block here — see how cf-realtime-monitor does it.
