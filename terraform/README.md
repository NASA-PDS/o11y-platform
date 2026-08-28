# PDS o11y-platform — Terraform

Deploys the shared observability infrastructure for the NASA Planetary Data System. Consumers connect via SSM — no cross-repo Terraform dependencies.

## Technical architecture

```mermaid
flowchart LR
    subgraph vpc["VPC (private subnets)"]
        SG["OpenSearch Security Group\n(HTTPS 443 inbound)"]
        OS["OpenSearch Domain\n(VPC endpoint)"]
    end

    subgraph ssm_in["SSM inputs (read only when the matching *_enabled flag is true)"]
        EC2ARN["/pds/o11y-cloudfront-batch/iam/ec2_role_arn"]
        FHARN["/pds/o11y-cloudfront-streaming/firehose/firehose-role-arn"]
        COGUP["/pds/cds-infra/cognito/user-pool/user-pool-id"]
        COGIP["/pds/cds-infra/cognito/user-pool/opensearch-dashboards-identity-pool-id"]
        COGAR["/pds/cds-infra/iam/roles/cognito-admin-role-arn"]
    end

    POL["IAM Access Policy\n(resource-based, conditional —\nabsent until a consumer is enabled)"]
    SSM_OUT["SSM outputs\n/pds/o11y-platform/opensearch\n/opensearch_endpoint\n/opensearch_arn\n/opensearch_security_group_id"]

    subgraph wa["o11y-cloudfront-batch"]
        LS["Logstash EC2"]
        EC2SG["EC2 Security Group\n(pre-existing MCP infra)"]
        WAIAM["iam/policies"]
    end

    subgraph cf["o11y-cloudfront-streaming"]
        FH["Kinesis Firehose"]
        FHSG["Firehose Security Group"]
    end

    subgraph dash["OpenSearch Dashboards (built-in)"]
        DB["Dashboards UI\n(https://endpoint/_dashboards)"]
    end

    subgraph cds["pdc-cds-infra"]
        COGPOOL["Cognito User Pool\n+ Identity Pool"]
    end

    EC2SG -->|"SG ingress rule\n(unconditional)"| SG
    SG --> OS
    EC2ARN -->|"IAM principal,\nif o11y_cloudfront_batch_enabled"| POL
    FHARN -->|"IAM principal,\nif o11y_cloudfront_streaming_enabled"| POL
    COGAR -->|"IAM principal,\nif dashboards_enabled"| POL
    COGUP -->|"if dashboards_enabled"| OS
    COGIP -->|"if dashboards_enabled"| OS
    POL --> OS
    OS --> SSM_OUT
    OS --> DB
    COGPOOL -->|"authenticates users"| DB
    SSM_OUT -.->|"endpoint, reads at plan time"| LS
    SSM_OUT -.->|"endpoint, reads at plan time"| FH
    SSM_OUT -.->|"arn, reads at plan time"| WAIAM
    SSM_OUT -.->|"security_group_id,\nreads at plan time"| FHSG
    FHSG -->|"o11y-cloudfront-streaming manages this rule:\naws_vpc_security_group_ingress_rule"| SG
    LS -->|"HTTPS"| SG
    FH -->|"HTTPS"| SG
```

Network access is controlled by Security Group ingress rules (port 443). The EC2 SG rule lives here, since the MCP EC2 SG is pre-existing shared infra; the Firehose SG rule is instead created and owned by o11y-cloudfront-streaming itself, as a separate `aws_vpc_security_group_ingress_rule` resource targeting this repo's SG by ID (read from SSM) — this repo no longer takes a Firehose SG ID as an input. API access is controlled by an IAM resource-based policy whose principals are role ARNs read from SSM at plan time, gated by the `o11y_cloudfront_batch_enabled` / `o11y_cloudfront_streaming_enabled` / `dashboards_enabled` flags (see [Access control](#access-control)) so the domain can bootstrap before any consumer exists. The domain's endpoint, ARN, and security group ID are published to SSM after deploy; consumers read them at Terraform plan time (dashed lines) with no shared state between repos.

**OpenSearch Dashboards** is exposed natively when `dashboards_enabled = true`. It uses Cognito for authentication via resources provisioned in `pdc-cds-infra` (the shared infra layer). Users log in at `https://<opensearch-endpoint>/_dashboards`. See [Dashboards](#dashboards) for the enablement sequence.

## Deployment flow

```mermaid
flowchart TD
    subgraph p1["Phase 1 — bootstrap (this repo)"]
        OS1["opensearch\nall *_enabled = false\n(~15-20 min)\npublishes endpoint → SSM"]
    end

    subgraph p2["Phase 2 — pdc-cds-infra (if Dashboards needed)"]
        CDS["cognito/user-pool\no11y_opensearch_dashboards_enabled = true\n(reads endpoint from SSM automatically,\npublishes identity-pool-id → SSM)"]
    end

    subgraph p2wa["Phase 2 — o11y-cloudfront-batch (parallel)"]
        IAM["iam/policies"]
        S3["S3 bucket"]
    end

    subgraph p2cf["Phase 2 — o11y-cloudfront-streaming (parallel)"]
        CFIAM["iam/ (own state, deploy first)"]
        CFMAIN["terraform apply\n(firehose, kinesis, lambda, CloudFront)"]
        CFIAM --> CFMAIN
    end

    subgraph p3["Phase 3 — grant access + Dashboards (this repo)"]
        OS2["opensearch\no11y_cloudfront_batch_enabled = true\no11y_cloudfront_streaming_enabled = true\ndashboards_enabled = true\n(reads identity-pool-id from SSM,\nenables FGAC + cognito_options, ~10 min)"]
    end

    subgraph p4["Phase 4 — o11y-cloudfront-batch"]
        LS["logstash EC2"]
    end

    OS1 -->|"endpoint → SSM"| CDS
    OS1 -->|"endpoint, arn, SG id → SSM"| p2wa
    OS1 -->|"endpoint, SG id → SSM"| p2cf
    CDS -->|"identity-pool-id → SSM"| OS2
    IAM -->|"ec2_role_arn → SSM"| OS2
    CFIAM -->|"firehose_role_arn → SSM"| OS2
    OS2 -->|"access policy now allows all"| LS
    OS2 -->|"access policy now allows all"| CFMAIN
    IAM --> LS
    S3 -->|"bucket → SSM"| LS
```

1. **(1) Bootstrap OpenSearch** — with all `*_enabled` flags `false`: `task opensearch:deploy VENUE=dev` (~15-20 min). Publishes endpoint, ARN, and SG ID to SSM. No access policy yet — expected.
2. **(2) Deploy in parallel** — all three can proceed as soon as Phase 1 finishes:
   - **pdc-cds-infra `cognito/user-pool`** *(if Dashboards needed)*: set `o11y_opensearch_dashboards_enabled = true` — reads the endpoint from SSM automatically, constructs the callback URL, creates the Identity Pool, and publishes its ID to SSM. No URL values in tfvars.
   - **o11y-cloudfront-batch**: `task iam:deploy VENUE=dev` (publishes `ec2_role_arn`), then `task s3:deploy VENUE=dev`
   - **o11y-cloudfront-streaming**: `iam/` module first (publishes `firehose_role_arn`), then root module
3. **(3) Grant access + enable Dashboards** — set `o11y_cloudfront_batch_enabled = true`, `o11y_cloudfront_streaming_enabled = true`, and `dashboards_enabled = true` in tfvars, then re-apply. Consumer flags are access-policy-only (seconds). `dashboards_enabled` also wires `cognito_options` (~10 min, config update not replacement). **⚠ Enabling FGAC is irreversible** — domain must be destroyed/recreated to disable.
4. **(4) Finish o11y-cloudfront-batch** — `task logstash:deploy VENUE=dev` — reads endpoint and bucket from SSM.

No manual URL values or `aws ssm put-parameter` seeding required anywhere — everything is SSM-driven via `*_enabled` flags.

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.10.0
- [Task](https://taskfile.dev) — `brew install go-task/tap/go-task`
- AWS credentials exported:
  ```bash
  eval $(aws configure export-credentials --profile <your-profile> --format env)
  unset AWS_PROFILE  # required for Terraform S3 backend compatibility
  ```

---

## Setup

tfvars are tracked in the `cds-infra-deploy` repo (private GitLab, not GitHub) at
`venues/<venue>/o11y-platform/opensearch.tfvars`, not in this repo — `*.tfvars` here is
gitignored. Point Task at a local checkout of that repo:

```bash
export CDS_INFRA_DEPLOY_DIR=/path/to/cds-infra-deploy
cd terraform/
task opensearch:plan VENUE=dev
```

For personal iteration before promoting values to `cds-infra-deploy`, pass `LOCAL=1` to use
this repo's own (gitignored) `opensearch/tfvars/<venue>.tfvars` instead:

```bash
cp opensearch/tfvars/dev.tfvars.example opensearch/tfvars/dev.tfvars
# Edit dev.tfvars: set domain_name, vpc_id, vpc_subnet_ids, ec2_security_group_name
task opensearch:plan VENUE=dev LOCAL=1
```

| Variable | Notes |
|---|---|
| `vpc_id`, `vpc_subnet_ids` | VPC where the OpenSearch endpoint is placed (private subnets) |
| `ec2_security_group_name` | MCP EC2 SG name — allows Logstash HTTPS inbound (pre-existing shared infra, unconditional) |
| `o11y_cloudfront_batch_enabled` | Set `false` for the initial bootstrap deploy; `true` once o11y-cloudfront-batch's `iam/policies` module has published `ec2_role_arn` — see [Access control](#access-control) |
| `o11y_cloudfront_streaming_enabled` | Set `false` for the initial bootstrap deploy; `true` once o11y-cloudfront-streaming's `iam/` module has published `firehose_role_arn` — see [Access control](#access-control) |
| `dashboards_enabled` | Set `false` initially; `true` once pdc-cds-infra `cognito/user-pool` has been deployed with the Dashboards callback URL — see [Dashboards](#dashboards). **Irreversible — enables FGAC permanently.** |

No Firehose SG ID input is needed — o11y-cloudfront-streaming creates its own ingress rule against this domain's SG (see [Technical architecture](#technical-architecture)).

---

## Deployment

### OpenSearch domain — 🔑 Power-User (~15-20 min)

```bash
cd terraform/

task opensearch:init    VENUE=dev
task opensearch:plan    VENUE=dev LOCAL=1
task opensearch:deploy  VENUE=dev LOCAL=1
task opensearch:endpoint             # confirm endpoint stored in SSM
```

After deploy, the endpoint, domain ARN, and security group ID are published to SSM automatically:
```
/pds/o11y-platform/opensearch/opensearch_endpoint
/pds/o11y-platform/opensearch/opensearch_arn
/pds/o11y-platform/opensearch/opensearch_security_group_id
```

See [Deployment flow](#deployment-flow) above for when to re-run this with `o11y_cloudfront_batch_enabled` / `o11y_cloudfront_streaming_enabled` set to `true`.

---

## Access control

Principals are read from SSM at plan time, each gated by a tfvars flag so this repo can bootstrap before any consumer exists. When `dashboards_enabled = true`, FGAC is also enabled on the domain (required by Cognito Dashboards auth).

| tfvars flag | SSM path (read only when flag is `true`) | Published by |
|---|---|---|
| `o11y_cloudfront_batch_enabled` | `/pds/o11y-cloudfront-batch/iam/ec2_role_arn` | o11y-cloudfront-batch `iam/policies` module |
| `o11y_cloudfront_streaming_enabled` | `/pds/o11y-cloudfront-streaming/firehose/firehose-role-arn` | o11y-cloudfront-streaming `iam/` module |
| `dashboards_enabled` | `/pds/cds-infra/iam/roles/cognito-admin-role-arn` | pdc-cds-infra `iam/roles` module |

All three default to `false`. With all false, `aws_opensearch_domain_policy` isn't created at all — an access policy with an empty `Principal.AWS` is invalid. The flags are independent; flip each as soon as the matching consumer or Cognito prereq is ready. See [Deployment flow](#deployment-flow) for the full sequence.

---

## Dashboards

OpenSearch Dashboards is exposed at `https://<opensearch-endpoint>/_dashboards` when `dashboards_enabled = true`. Users authenticate via the shared PDS Cognito User Pool managed in [pdc-cds-infra](https://github.com/NASA-PDS/pdc-cds-infra).

### Prerequisites

First, complete the Phase 1 bootstrap deploy so the OpenSearch endpoint is in SSM. Then in pdc-cds-infra, deploy `terraform/cognito/user-pool/` with `o11y_opensearch_dashboards_enabled = true` — it reads the endpoint from SSM at `/pds/o11y-platform/opensearch/opensearch_endpoint` and constructs the callback URL automatically. No manual URL values needed.

### Enabling Dashboards

Once the pdc-cds-infra Cognito resources exist (Identity Pool ID in SSM), set `dashboards_enabled = true` in tfvars and apply:

```bash
task opensearch:plan   VENUE=dev
task opensearch:deploy VENUE=dev   # ~10 min — config update, not a domain replacement
```

This enables FGAC on the domain, attaches `cognito_options`, and creates an `es.amazonaws.com` IAM service role (`${domain_name}-opensearch-cognito`) with `AmazonOpenSearchServiceCognitoAccess`.

> **⚠ Irreversible:** Enabling FGAC cannot be undone. The domain must be destroyed and recreated to revert to non-FGAC mode. Only enable this once you intend it permanently for the venue.

### User management

Users are managed in pdc-cds-infra `terraform/cognito/user-and-groups/`. The Cognito admin role (`pds_cds_admin_through_cognito`) gets full Dashboards access by default via the FGAC master user ARN.

---

## Teardown

```bash
task opensearch:destroy VENUE=dev   # destroys all indexed data — irreversible
```

---

## Architecture notes

- **State** — S3 backend, key `o11y-platform/opensearch.tfstate`.
- **VPC/SG values** are in tfvars. TODO: source EC2 SG from SSM under `/pds/cds-infra/vpc/security_groups/` once MCP publishes it.
- **Adding a new consumer** — publish its role ARN to SSM, add a `data "aws_ssm_parameter"` block in `opensearch/main.tf`, add the ARN to the access policy principals, and add an SG ingress rule if needed.
