# PDS o11y-platform - Deployment Runbook

This is the single runbook for deploying, updating, and testing the PDS observability stack: the shared OpenSearch domain in this repo plus its two consumers, [o11y-cloudfront-batch](https://github.com/NASA-PDS/o11y-cloudfront-batch) and [o11y-cloudfront-streaming](https://github.com/NASA-PDS/o11y-cloudfront-streaming), and the CloudFront wiring in [pdc-cds-infra](https://github.com/NASA-PDS/pdc-cds-infra).

Each component repo documents its own modules (inputs, apply, verify, update). This runbook owns the **order** of phases, the **permissions** each needs, and the **cross-repo SSM contract**. It links to the component docs instead of repeating them.

| I want to... | Go to |
|---|---|
| Deploy a venue from scratch | [Initial deployment](#initial-deployment) |
| Change an already-deployed component | [Updating](#updating) |
| Check that a deployment works | [Testing](#testing) |
| See which SSM parameters connect the repos | [SSM contract](#ssm-contract) |

## Architecture

```mermaid
flowchart LR
    subgraph vpc["VPC (private subnets)"]
        SG["OpenSearch Security Group\n(HTTPS 443 inbound)"]
        OS["OpenSearch Domain\n(VPC endpoint)"]
    end

    subgraph ssm_in["SSM inputs (read only when the matching *_enabled flag is true)"]
        EC2ARN["batch instance-role-arn"]
        LSSGID["batch logstash_security_group_id"]
        FHARN["streaming firehose-role-arn"]
        FHSGID["streaming firehose-security-group-id"]
    end

    POL["IAM access policy\n(absent until a consumer is enabled)"]
    SSM_OUT["SSM outputs\nopensearch_endpoint\nopensearch_arn\nopensearch_security_group_id"]

    subgraph wa["o11y-cloudfront-batch"]
        LS["Logstash EC2"]
        WAIAM["iam"]
    end

    subgraph cf["o11y-cloudfront-streaming"]
        FH["Kinesis Firehose"]
    end

    LSSGID -->|"Logstash SG ingress rule"| SG
    FHSGID -->|"Firehose SG ingress rule"| SG
    SG --> OS
    EC2ARN -->|"IAM principal"| POL
    FHARN -->|"IAM principal"| POL
    POL --> OS
    OS --> SSM_OUT
    SSM_OUT -.->|"endpoint"| LS
    SSM_OUT -.->|"arn"| WAIAM
    LS -->|"HTTPS"| SG
    FH -->|"HTTPS"| SG
```

- **Network:** the domain is VPC-only. Security group ingress rules (port 443) for Logstash and Firehose live in this module. Each consumer's security group ID is read from SSM at plan time.
- **API:** an IAM resource-based policy allows the consumer role ARNs, read from SSM at plan time.
- **Gating:** both are controlled by `o11y_cloudfront_batch_enabled` and `o11y_cloudfront_streaming_enabled`, so the domain can bootstrap before any consumer exists.
- **Discovery:** consumers read the domain's SSM outputs at plan time. There is no shared Terraform state between repos.
- **Ops access:** the AWS-hosted [OpenSearch UI Application](#phase-8---opensearch-ui-application), not the built-in `/_dashboards` endpoint.

## Prerequisites

Tools: [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.10.0, [Terragrunt](https://terragrunt.gruntwork.io/docs/getting-started/install/) >= 0.55, [Task](https://taskfile.dev) (`brew install go-task/tap/go-task`), and the AWS CLI.

Checkouts: `cds-infra-deploy` (all venue inputs live there as `venues/<venue>/<repo>/<module>/terragrunt.hcl`), this repo (for `scripts/smoke-test.sh`), and `o11y-cloudfront-streaming` (for its Kinesis smoke test in Phase 6).

Set these once per shell session. Every command in this runbook uses them.

```bash
VENUE="dev"                                   # dev | test | prod
REGION="us-west-2"
PROFILE_NAME="<your-sso-profile>"
CDS_INFRA_DEPLOY_DIR="<path-to-cds-infra-deploy-checkout>"
O11Y_PLATFORM_DIR="<path-to-o11y-platform-checkout>"
O11Y_STREAMING_DIR="<path-to-o11y-cloudfront-streaming-checkout>"

# The Terraform S3 backend needs exported credentials with AWS_PROFILE unset.
eval $(aws configure export-credentials --profile "${PROFILE_NAME}" --format env)
unset AWS_PROFILE

# Read one SSM parameter value (used by the Verify steps).
ssm_get() { aws ssm get-parameter --region "${REGION}" --name "$1" --query Parameter.Value --output text; }
```

`task plan` and `task apply` commands run from `cds-infra-deploy`:

```bash
cd "${CDS_INFRA_DEPLOY_DIR}"
```

Each phase below states the permission tier it needs. Switch to a role in that tier and re-export credentials before the phase.

## Required AWS permissions

A principal needs the highest tier of every module it deploys.

| Tier | Who | Required when |
|---|---|---|
| **Admin** | Ops/Admin SSO role with `iam:CreateRole` | Any IAM *creation* module: the `iam` modules in the consumer repos |
| **Platform Engineer** | SSO role with `iam:PassRole` (not `CreateRole`) | Any module that assigns an existing role ARN to a non-IAM resource: Firehose, Lambda, EC2 instance profile, CloudFront real-time log config |
| **Power User** | Standard `Project-Power-User` SSO | Everything else: OpenSearch bootstrap, S3, Kinesis, CloudWatch, SSM reads |

`iam:PassRole` is not `iam:CreateRole`. A module that only reads a role ARN from SSM and assigns it to a service resource is Platform Engineer, not Admin.

## SSM contract

Parameters that cross a repo boundary. Each repo publishes what the next phase reads, and consumers read them at plan time. Parameters used inside a single component are documented in that component's README.

| Parameter path | Published by (phase) | Read by | Read when |
|---|---|---|---|
| `/pds/o11y-platform/opensearch/opensearch_endpoint` | platform `opensearch` (1) | batch `logstash` | always |
| `/pds/o11y-platform/opensearch/opensearch_arn` | platform `opensearch` (1) | batch `iam` | always |
| `/pds/o11y-platform/opensearch/opensearch_security_group_id` | platform `opensearch` (1), when `vpc_enabled` | `scripts/smoke-test.sh` | - |
| `/pds/o11y-cloudfront-batch/iam/roles/ec2/instance-role-arn` | batch `iam` (2a) | platform `opensearch`; `pds-main` | `o11y_cloudfront_batch_enabled`; `enable_o11y_batch` |
| `/pds/o11y-cloudfront-batch/ec2/logstash_security_group_id` | batch `logstash` (3) | platform `opensearch` | `o11y_cloudfront_batch_enabled` and `vpc_enabled` |
| `/pds/o11y-cloudfront-streaming/firehose/firehose-role-arn` | streaming `iam/` (2b) | platform `opensearch`; `pds-main` | `o11y_cloudfront_streaming_enabled`; `enable_o11y_streaming` |
| `/pds/o11y-cloudfront-streaming/firehose/firehose-security-group-id` | streaming `streaming/` (4) | platform `opensearch` | `o11y_cloudfront_streaming_enabled` and `vpc_enabled` |
| `/pds/o11y-cloudfront-streaming/cloudfront/cloudfront-role-arn` | streaming `iam/` (2b) | `pds-main` | `enable_o11y_streaming` |
| `/pds/o11y-cloudfront-streaming/kinesis/kinesis-stream-arn` | streaming `iam/` (2b); the ARN is computed, the stream is created in phase 4 | `pds-main` | `enable_o11y_streaming` |
| `/pds/pdc-cds-infra/s3/pds-logs-bucket-arn` | `pds-main` (6); seeded by hand before phase 2b on a first deploy | streaming `iam/` and `streaming/` | always |

Streaming looks up the OpenSearch domain by name, not through SSM.

## Deployment flow

> **`opensearch` is always applied twice.** Phase 1 creates the domain with every `*_enabled` flag `false`, because the consumers don't exist yet. Phase 5 sets the flags to `true` after the consumers have published their SSM parameters. Phase 5 is an access-policy and ingress-rule update only; the domain is not redeployed.
>
> Enabling a flag before its parameters exist fails the plan with a missing-parameter error. That error means an earlier phase is incomplete.
>
> | Flag | Phases that must already be applied |
> |---|---|
> | `o11y_cloudfront_batch_enabled` | batch `iam` (2a) and `logstash` (3) |
> | `o11y_cloudfront_streaming_enabled` | streaming `iam/` (2b) and `streaming/` (4) |
>
> Until a flag is on, that consumer has no access-policy entry and no ingress rule, so it cannot reach the domain.

```mermaid
flowchart TD
    P1["1. opensearch, all flags false\n(Power User, ~15-20 min)"]
    P2a["2a. batch iam\n(Admin)"]
    P2b["2b. streaming iam/\n(Admin)"]
    P3["3. batch s3, then logstash EC2\n(Power User, then Platform Eng)"]
    P4["4. streaming streaming/\n(Platform Eng)"]
    P5["5. opensearch re-apply, flags true\n(Power User, seconds)"]
    P6["6. pdc-cds-infra pds-main\n(Platform Eng)"]
    P7["7. Logstash on-instance deploy + verify\n(pdsops via bastion)"]
    P8["8. OpenSearch UI Application\n(Power User, manual)"]
    P9["9. End-to-end verify"]

    P1 --> P2a & P2b
    P2a --> P3
    P2b --> P4
    P3 --> P5
    P4 --> P5
    P5 --> P6
    P6 --> P7
    P7 --> P8
    P8 --> P9
```

Phase 6 runs last, after every component it points at exists. See [Phase 6](#phase-6---cloudfront-pds-main) for why.

## Initial deployment

Complete the phases in order. Run each Verify step and get the expected result before moving on. Replace `dev` only by changing `VENUE` in [Prerequisites](#prerequisites).

### Phase 1 - Bootstrap OpenSearch

**Tier:** Power User. **Time:** about 15-20 minutes.

Creates the VPC-only domain and its security group, and publishes the endpoint, ARN, and security group ID to SSM. No consumer is enabled. Venue inputs are in `venues/<venue>/o11y-platform/opensearch/terragrunt.hcl`; the inputs shape is in the [opensearch module README](opensearch/README.md#deploy).

1. Confirm both consumer flags are `false` or unset:

   ```bash
   grep -nE 'o11y_cloudfront_(batch|streaming)_enabled' \
     "venues/${VENUE}/o11y-platform/opensearch/terragrunt.hcl"
   ```

2. Plan and apply:

   ```bash
   task plan  VENUE="${VENUE}" COMPONENT=o11y-platform/opensearch
   task apply VENUE="${VENUE}" COMPONENT=o11y-platform/opensearch
   ```

**Verify**

```bash
bash "${O11Y_PLATFORM_DIR}/scripts/smoke-test.sh" "${VENUE}"
```

Expected: `All 7 check(s) passed.` The script checks the three SSM parameters, the security group, domain status, and cluster health (Green or Yellow). If a check fails, wait for the domain to leave `Processing` and re-run; if an SSM parameter is missing, the apply did not complete.

### Phase 2 - IAM

**Tier:** Admin. Phases 2a and 2b are independent and can run in either order.

Each consumer's `iam` module creates its roles and publishes their ARNs to SSM. Module details: [batch `iam`](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/terraform/README.md), [streaming `iam/`](https://github.com/NASA-PDS/o11y-cloudfront-streaming/blob/main/terraform/iam/README.md).

**2a - o11y-cloudfront-batch**

```bash
task plan  VENUE="${VENUE}" COMPONENT=o11y-cloudfront-batch/iam
task apply VENUE="${VENUE}" COMPONENT=o11y-cloudfront-batch/iam
```

Verify:

```bash
ssm_get /pds/o11y-cloudfront-batch/iam/roles/ec2/instance-role-arn
```

Expected: an IAM role ARN. `ParameterNotFound` means the apply did not complete.

**2b - o11y-cloudfront-streaming**

1. On a first deploy only, confirm the logs bucket ARN parameter exists. Streaming `iam/` reads it.

   ```bash
   ssm_get /pds/pdc-cds-infra/s3/pds-logs-bucket-arn
   ```

   Expected: `arn:aws:s3:::pds-logs-<venue>`. If the result is `ParameterNotFound`, seed it once. Phase 6 takes the parameter over without an import.

   ```bash
   aws ssm put-parameter \
     --region "${REGION}" \
     --name /pds/pdc-cds-infra/s3/pds-logs-bucket-arn \
     --value "arn:aws:s3:::pds-logs-${VENUE}" \
     --type String
   ```

2. Plan and apply:

   ```bash
   task plan  VENUE="${VENUE}" COMPONENT=o11y-cloudfront-streaming/iam
   task apply VENUE="${VENUE}" COMPONENT=o11y-cloudfront-streaming/iam
   ```

Verify:

```bash
for P in cloudfront/cloudfront-role-arn firehose/firehose-role-arn kinesis/kinesis-stream-arn; do
  ssm_get "/pds/o11y-cloudfront-streaming/${P}"
done
```

Expected: three ARNs. The Kinesis ARN is computed; the stream itself does not exist until Phase 4. Do not deploy `streaming/` yet.

### Phase 3 - Batch S3 and Logstash EC2

**Tier:** Power User for `s3`, Platform Engineer for `logstash` (`iam:PassRole` to the EC2 instance profile). Needs Phases 1 and 2a.

`s3` creates the bucket that receives PDS node access logs. `logstash` creates the EC2 instance and its security group, and publishes the security group ID. This phase creates the instance only; Logstash is installed in Phase 7.

```bash
task plan  VENUE="${VENUE}" COMPONENT=o11y-cloudfront-batch/s3
task apply VENUE="${VENUE}" COMPONENT=o11y-cloudfront-batch/s3

task plan  VENUE="${VENUE}" COMPONENT=o11y-cloudfront-batch/logstash
task apply VENUE="${VENUE}" COMPONENT=o11y-cloudfront-batch/logstash
```

**Verify**

```bash
ssm_get /pds/o11y-cloudfront-batch/s3/bucket_name
ssm_get /pds/o11y-cloudfront-batch/ec2/logstash_security_group_id
```

Expected: a bucket name and a `sg-` ID. Module details: [batch Terraform README](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/terraform/README.md).

### Phase 4 - Streaming

**Tier:** Platform Engineer (`iam:PassRole` to Firehose and Lambda). Needs Phases 1 and 2b.

Creates the Kinesis stream, Lambda transform, Firehose delivery stream, and the Firehose security group. The apply succeeds before OpenSearch access is granted, but Firehose cannot write to the domain until Phase 5.

```bash
task plan  VENUE="${VENUE}" COMPONENT=o11y-cloudfront-streaming/streaming
task apply VENUE="${VENUE}" COMPONENT=o11y-cloudfront-streaming/streaming
```

**Verify**

```bash
ssm_get /pds/o11y-cloudfront-streaming/firehose/firehose-security-group-id

aws kinesis describe-stream-summary --region "${REGION}" \
  --stream-name pds-o11y-cloudfront-streaming-kinesis \
  --query StreamDescriptionSummary.StreamStatus --output text
```

Expected: a `sg-` ID and `ACTIVE`. Module details: [streaming Terraform README](https://github.com/NASA-PDS/o11y-cloudfront-streaming/blob/main/terraform/README.md).

### Phase 5 - Grant consumers OpenSearch access

**Tier:** Power User. **Time:** seconds. Needs Phases 2a, 2b, 3, and 4.

The second `opensearch` apply. It adds both consumer role ARNs to the access policy and both security groups to the ingress rules.

1. In `cds-infra-deploy`, set both flags to `true` in `venues/<venue>/o11y-platform/opensearch/terragrunt.hcl`:

   ```hcl
   o11y_cloudfront_batch_enabled     = true
   o11y_cloudfront_streaming_enabled = true
   ```

2. Plan, and confirm the plan only changes the access policy and adds two ingress rules. It must not replace `aws_opensearch_domain.this`.

   ```bash
   task plan  VENUE="${VENUE}" COMPONENT=o11y-platform/opensearch
   task apply VENUE="${VENUE}" COMPONENT=o11y-platform/opensearch
   ```

**Verify**

```bash
DOMAIN_NAME=$(ssm_get /pds/o11y-platform/opensearch/opensearch_arn | awk -F/ '{print $NF}')
aws opensearch describe-domain --region "${REGION}" --domain-name "${DOMAIN_NAME}" \
  --query 'DomainStatus.AccessPolicies' --output text

OS_SG_ID=$(ssm_get /pds/o11y-platform/opensearch/opensearch_security_group_id)
aws ec2 describe-security-group-rules --region "${REGION}" \
  --filters "Name=group-id,Values=${OS_SG_ID}" \
  --query 'SecurityGroupRules[?IsEgress==`false`].[ReferencedGroupInfo.GroupId,FromPort]' \
  --output text
```

Expected: the access policy lists both role ARNs (the batch `instance-role-arn` and the streaming `firehose-role-arn`). The ingress rules show two rows on port `443`, one for the Logstash security group and one for the Firehose security group.

### Phase 6 - CloudFront (`pds-main`)

**Tier:** Platform Engineer (`iam:PassRole` for the CloudFront real-time log config). Needs Phases 2a, 2b, 4, and 5.

Applies `cloudfront/pds-main` from [pdc-cds-infra](https://github.com/NASA-PDS/pdc-cds-infra) with both o11y flags on. It:

- creates the CloudFront real-time log config that sends records to the Kinesis stream (`enable_o11y_streaming`);
- adds bucket policy statements on `pds-logs-<venue>`: `AllowO11yBatchLogstashRead` lets the Logstash role read the CloudFront access-log prefix (`enable_o11y_batch`), and `AllowFirehoseWrite` lets Firehose write its S3 backup (`enable_o11y_streaming`);
- manages `/pds/pdc-cds-infra/s3/pds-logs-bucket-arn`.

**Why this phase is last before the Logstash deploy:** it points the shared CloudFront distribution at the Kinesis stream and opens the logs bucket to Logstash. Running it after Phases 4 and 5 means the stream exists, OpenSearch already accepts both consumers, and a failure is easy to back out by setting both flags to `false`. See the pdc-cds-infra [o11y integration](https://github.com/NASA-PDS/pdc-cds-infra/blob/main/terraform/cloudfront/pds-main/README.md#o11y-integration) section for the module inputs.

`enable_o11y_batch` is needed only if Logstash ingests CloudFront logs from `pds-logs-<venue>` (`S3_CF_BUCKET_NAME` is set in the Logstash environment).

1. Confirm both flags are `true`. The module default is `true`; check the venue file for an override.

   ```bash
   grep -nE 'enable_o11y_(batch|streaming)' \
     "venues/${VENUE}/pdc-cds-infra/cloudfront/pds-main/terragrunt.hcl"
   ```

2. Plan and apply:

   ```bash
   task plan  VENUE="${VENUE}" COMPONENT=pdc-cds-infra/cloudfront/pds-main
   task apply VENUE="${VENUE}" COMPONENT=pdc-cds-infra/cloudfront/pds-main
   ```

**Verify**

```bash
aws cloudfront list-realtime-log-configs \
  --query 'RealtimeLogConfigs.Items[].Name' --output text

aws s3api get-bucket-policy --bucket "pds-logs-${VENUE}" \
  --query Policy --output text
```

Expected: `pds-cloudfront-realtime-log-config` is listed, and the bucket policy contains the Sids `AllowO11yBatchLogstashRead` and `AllowFirehoseWrite`. The second command needs `s3:GetBucketPolicy`. Allow several minutes for the distribution to finish deploying before expecting records.

Then confirm records reach the Kinesis stream:

```bash
bash "${O11Y_STREAMING_DIR}/scripts/smoke-test-realtime-stream.sh" "${VENUE}"
```

Expected: `PASS: <n> record(s) reached the Kinesis stream`, within about 3 minutes. The script requests a few URLs under `/data` and polls the stream's `IncomingRecords` metric. On `FAIL`, the distribution may still be deploying; wait and re-run. The script does not check OpenSearch; that is [Phase 9](#phase-9---end-to-end-verify).

### Phase 7 - Deploy Logstash and verify

**Tier:** shell access to the EC2 as `pdsops`, through the bastion. Needs Phases 3, 5, and 6.

Installs and starts Logstash on the instance created in Phase 3. This runs on the instance, not through Terragrunt. Follow the batch repo; do not copy its steps here:

1. [Access model](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/terraform/logstash/README.md#access-model) to reach the instance.
2. [First-boot setup](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/terraform/logstash/README.md#first-boot-setup) to deploy.
3. [Verify the deployment](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/terraform/logstash/README.md#verify-the-deployment).

Expected: `scripts/smoke-test.sh` on the instance reports every check passing. Phases 5 and 6 are already applied, so an OpenSearch or S3 access failure here is a real fault; see the batch [Operations Runbook](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/docs/operations.md#troubleshooting).

### Phase 8 - OpenSearch UI Application

**Tier:** Power User. All steps are manual (console and CLI).

The OpenSearch UI Application is an AWS-hosted web UI that reaches the VPC-only domain without a public endpoint. IAM Identity Center is not enabled in PDS accounts, so it uses IAM auth: IAM role ARNs are granted directly as admins. No Terraform resource exists yet ([hashicorp/terraform-provider-aws#45082](https://github.com/hashicorp/terraform-provider-aws/issues/45082)).

**Step 1 - Authorize VPC access (once per domain).** The AWS console features for a VPC domain, including the Indexes tab, cannot reach it until the `application.opensearchservice.amazonaws.com` service principal is authorized. The Terraform provider cannot express this ([hashicorp/terraform-provider-aws#41879](https://github.com/hashicorp/terraform-provider-aws/issues/41879)).

```bash
DOMAIN_NAME=$(ssm_get /pds/o11y-platform/opensearch/opensearch_arn | awk -F/ '{print $NF}')

aws opensearch authorize-vpc-endpoint-access --region "${REGION}" \
  --domain-name "${DOMAIN_NAME}" \
  --service application.opensearchservice.amazonaws.com

aws opensearch list-vpc-endpoint-access --region "${REGION}" \
  --domain-name "${DOMAIN_NAME}"
```

Expected: the second command lists `application.opensearchservice.amazonaws.com`.

**Step 2 - Create the application (console).**

1. Open **Amazon OpenSearch Service > OpenSearch UI (Dashboards) > Create application**.
2. Set **Application name** to `pds-<venue>-o11y-ui`.
3. Leave **Authentication with IAM Identity Center** unchecked.
4. Under **OpenSearch application admins**, choose **Grant administrator's permission to specific user(s)**, select **IAM users**, and add the ops IAM role ARN(s).
5. Choose **Create**.

**Step 3 - Associate the domain.** On the application page choose **Manage data sources**, select the domain (the value of `${DOMAIN_NAME}`), then **Next > Save**. **Launch Application** becomes active once a data source is associated.

**Verify:** launch the application, open **Dev Tools**, and run:

```text
GET _cluster/health
```

Expected: `"status"` is `green` or `yellow`. A 403 means the role you are using is not allowed on the domain; grant it in Step 4.

**Step 4 - Grant ops roles domain access (only if Verify returns 403).** With IAM auth the application passes the caller's IAM identity to the domain, so each operator role must be allowed on the domain.

1. In `cds-infra-deploy`, add the role to `ops_role_arns` in `venues/<venue>/o11y-platform/opensearch/terragrunt.hcl`:

   ```hcl
   ops_role_arns = ["arn:aws:iam::<account-id>:role/<role-name>"]
   ```

   Use the IAM role ARN. An `arn:...:sts::...:assumed-role/...` ARN fails the plan with `Invalid value for variable "ops_role_arns"`, because it does not match the role's sessions.

2. Plan and apply:

   ```bash
   task plan  VENUE="${VENUE}" COMPONENT=o11y-platform/opensearch
   task apply VENUE="${VENUE}" COMPONENT=o11y-platform/opensearch
   ```

3. Re-run the Verify command above.

Each listed role gets `es:ESHttp*` on the domain and all paths under it: every HTTP method on every index. This is the same access the consumer roles have. Fine-grained access control is off, so there is no read-only or per-index tier. Control-plane actions such as `es:DeleteDomain` are not granted.

### Phase 9 - End-to-end verify

**Tier:** the ops role from Phase 8.

Confirms both pipelines are delivering documents. Generate traffic first: request a few URLs under `/data` through the CloudFront distribution. The real-time log config is attached to the `/data*` and `/data/store/img*` cache behaviors.

In OpenSearch UI **Dev Tools**:

```text
GET _cat/indices?v
```

Expected: the streaming index appears within minutes of traffic. The batch index appears after Logstash processes the next delivered log files.

| Pipeline | Index | Check |
|---|---|---|
| Streaming | `pds-o11y-cloudfront-streaming-index*` (one per day) | `docs.count` grows when you re-run the command |
| Batch | `<INDEX_PREFIX>-YYYY-MM` (one per month; the prefix is set in the Logstash environment) | `docs.count` is greater than 0 |

If an index is missing, find the failing hop:

| Missing | Check | Where |
|---|---|---|
| Streaming index | Real-time log config attached and distribution deployed (Phase 6); Firehose delivery errors | [streaming Terraform README](https://github.com/NASA-PDS/o11y-cloudfront-streaming/blob/main/terraform/README.md#troubleshooting) |
| Batch index | Logstash service, pipeline stats, bad-log file | batch [Operations Runbook](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/docs/operations.md#monitoring) |

## Updating

Re-run only the affected phase. Each component README owns the procedure for its own change; this table only says where to look.

| Change | Procedure | Notes |
|---|---|---|
| OpenSearch engine version, node count, instance type | [opensearch README: Upgrade](opensearch/README.md#upgrade) | Engine upgrade is a blue/green update, about 30 minutes in `Processing` |
| Consumer role or security group recreated | Re-run [Phase 5](#phase-5---grant-consumers-opensearch-access) | The SSM value changes, so the access policy and ingress rule must follow |
| Operator roles with domain access | Edit `ops_role_arns`, then [Phase 8, Step 4](#phase-8---opensearch-ui-application) | Access-policy update only |
| Batch IAM, S3, or Logstash instance | [batch Terraform README](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/terraform/README.md) (each module has an Update note) | A `logstash_version` change replaces the instance |
| Logstash pipeline config or `regexes.yaml` | batch [Update pipeline configuration](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/docs/operations.md#update-pipeline-configuration) | No Terraform change. Test first with the [pipeline tests](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/tests/README.md#running-the-integration-tests-with-docker) |
| Streaming Lambda, Kinesis, Firehose, or IAM | [streaming Terraform README: Updating](https://github.com/NASA-PDS/o11y-cloudfront-streaming/blob/main/terraform/README.md#updating) | |
| CloudFront log wiring or bucket access | pdc-cds-infra [`pds-main` README](https://github.com/NASA-PDS/pdc-cds-infra/blob/main/terraform/cloudfront/pds-main/README.md#o11y-integration) | |
| EC2, S3, or IAM module version | [pdc-tf-modules](https://github.com/NASA-PDS/pdc-tf-modules) | Update the module reference in the consuming component, then re-run its phase |

## Testing

| What | Test | When |
|---|---|---|
| OpenSearch domain | `scripts/smoke-test.sh` ([Phase 1](#phase-1---bootstrap-opensearch)) | After every `opensearch` apply that changes the domain |
| Cross-repo wiring | Verify steps in Phases 5 and 6 | After changing a flag, role, or security group |
| Logstash pipeline logic | batch [`tests/README.md`](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/tests/README.md#running-the-integration-tests-with-docker) | Before deploying any pipeline change |
| Logstash on the instance | [Verify the deployment](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/terraform/logstash/README.md#verify-the-deployment) | After each Logstash deploy |
| Data flow, both pipelines | [Phase 9](#phase-9---end-to-end-verify) | After an initial deployment or any change to the path |

## Teardown

Destroying the domain deletes all indexed data and is irreversible.

1. Set `enable_o11y_batch` and `enable_o11y_streaming` to `false` in the `pds-main` venue file and apply `pdc-cds-infra/cloudfront/pds-main`.
2. Destroy the consumers in reverse phase order: streaming `streaming/`, streaming `iam/`, batch `logstash`, batch `s3`, batch `iam`. Roles must outlive the resources that use them. Per-component notes are in each repo's README.
3. Destroy the domain:

   ```bash
   task destroy VENUE="${VENUE}" COMPONENT=o11y-platform/opensearch
   ```

## Architecture notes

- **State:** S3 backend, key `o11y-platform/opensearch.tfstate`. Bucket, region, and lock come from Terragrunt in `cds-infra-deploy`.
- **Venue inputs** (VPC, subnets, flags) are Terragrunt inputs in `cds-infra-deploy`. The `opensearch/tfvars/*.tfvars.example` files are a reference for plain Terraform, not the operational path.
- **Adding a consumer:** the consumer publishes its role ARN (and security group ID, if it needs VPC access) to SSM. This module gets a `<consumer>_enabled` variable (default `false`), a `data "aws_ssm_parameter"` block gated on it, an entry in `local.opensearch_access_principals`, and a gated `aws_vpc_security_group_ingress_rule`. Add the new parameters to the [SSM contract](#ssm-contract) and a phase to this runbook.
