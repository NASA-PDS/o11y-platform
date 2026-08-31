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

    subgraph p2a["Phase 2a — o11y-cloudfront-batch (parallel with 2b/2c)"]
        IAM["iam/policies\npublishes ec2_role_arn → SSM"]
        S3["s3\ncreates log bucket, sets CloudFront delivery policy\npublishes bucket name → SSM"]
        IAM --> S3
    end

    subgraph p2b["Phase 2b — o11y-cloudfront-streaming IAM (parallel with 2a/2c)"]
        CFIAM["iam/\npublishes firehose_role_arn,\nkinesis_stream_arn → SSM"]
    end

    subgraph p2c["Phase 2c — pdc-cds-infra Cognito (parallel, if Dashboards needed)"]
        CDS["cognito/user-pool\no11y_opensearch_dashboards_enabled = true\nreads endpoint from SSM,\npublishes identity-pool-id → SSM"]
    end

    subgraph p3["Phase 3 — pdc-cds-infra CloudFront"]
        CF["cloudfront/pds-main\nenable_o11y_batch = true\nenable_realtime_logging = true\n(reads ec2_role_arn + kinesis_stream_arn from SSM,\nattaches batch log delivery + real-time logging)"]
    end

    subgraph p4["Phase 4 — o11y-cloudfront-streaming root + grant access (this repo)"]
        CFMAIN["o11y-cloudfront-streaming root\n(firehose, kinesis, lambda — CloudFront now sending to stream)"]
        OS2["opensearch\no11y_cloudfront_batch_enabled = true\no11y_cloudfront_streaming_enabled = true\ndashboards_enabled = true\n(~10 min if dashboards_enabled)"]
    end

    subgraph p5["Phase 5 — o11y-cloudfront-batch logstash"]
        LS["logstash EC2\nreads endpoint + bucket from SSM"]
    end

    OS1 -->|"endpoint, arn, SG id → SSM"| p2a
    OS1 -->|"endpoint, SG id → SSM"| p2b
    OS1 -->|"endpoint → SSM"| p2c
    IAM -->|"ec2_role_arn → SSM"| CF
    S3 -->|"bucket policy allows CloudFront delivery"| CF
    CFIAM -->|"kinesis_stream_arn → SSM"| CF
    CDS -->|"identity-pool-id → SSM"| OS2
    CF -->|"CloudFront now writing batch logs"| CFMAIN
    CF -->|"CloudFront now writing realtime logs to Kinesis"| CFMAIN
    CFIAM -->|"firehose_role_arn → SSM"| OS2
    IAM -->|"ec2_role_arn → SSM"| OS2
    CFMAIN --> OS2
    OS2 -->|"access policy now allows all"| LS
    S3 -->|"bucket name → SSM"| LS
```

1. **(1) Bootstrap OpenSearch** — `task opensearch:deploy VENUE=dev` with all `*_enabled = false` (~15-20 min). Publishes endpoint, ARN, and SG ID to SSM. No access policy yet — expected.
2. **(2a/2b/2c) Deploy in parallel** — all three can start immediately after Phase 1:
   - **o11y-cloudfront-batch** `iam` then `s3` — `iam` publishes `ec2_role_arn`; `s3` creates the log bucket and sets its CloudFront delivery policy (CloudFront needs permission to write access logs to it)
   - **o11y-cloudfront-streaming** `iam` only — publishes `firehose_role_arn` and `kinesis_stream_arn` to SSM; stop here, don't deploy the root module yet
   - **pdc-cds-infra `cognito/user-pool`** *(if Dashboards needed)* — `o11y_opensearch_dashboards_enabled = true` reads endpoint from SSM, publishes Identity Pool ID
3. **(3) pdc-cds-infra CloudFront** — deploy `cloudfront/pds-main` with `enable_o11y_batch = true` and `enable_realtime_logging = true`. Reads `ec2_role_arn` (for batch log delivery to S3) and `kinesis_stream_arn` (for real-time logging) from SSM. After this, CloudFront is actively writing access logs to the S3 bucket and real-time logs to the Kinesis stream.
4. **(4) o11y-cloudfront-streaming root + grant OpenSearch access** — now that CloudFront is sending to the stream, deploy the o11y-cloudfront-streaming root module (Firehose, Lambda, etc.). Then re-apply this repo with `o11y_cloudfront_batch_enabled = true`, `o11y_cloudfront_streaming_enabled = true`, and optionally `dashboards_enabled = true`. Consumer flags are access-policy-only (seconds); `dashboards_enabled` triggers `cognito_options` (~10 min). **⚠ Enabling FGAC is irreversible.**
5. **(5) o11y-cloudfront-batch logstash** — `task logstash:deploy VENUE=dev` — reads OpenSearch endpoint and S3 bucket name from SSM.

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
