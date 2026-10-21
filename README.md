# Planetary Data Cloud (PDC) o11y-platform

Shared OpenSearch-backed observability platform for the Planetary Data Cloud. Aggregates logs from PDS services — batch node access logs via Logstash and CloudFront real-time logs via Kinesis Firehose.

## Architecture

```mermaid
flowchart LR
    subgraph batch["o11y-cloudfront-batch"]
        LS["Logstash EC2"]
    end

    subgraph obs["o11y-platform"]
        OS["OpenSearch"]
    end

    subgraph streaming["o11y-cloudfront-streaming"]
        FH["Kinesis Firehose"]
    end

    DASH["OpenSearch UI\nDashboards"]

    LS -->|"ECS v8 events"| OS
    FH -->|"CF real-time logs"| OS
    OS --> DASH
```

OpenSearch is a shared platform — both o11y-cloudfront-batch and o11y-cloudfront-streaming write to it. Consumers discover the endpoint via SSM with no shared Terraform state between repos. See [`terraform/README.md`](terraform/README.md) for the full technical architecture and AWS resource details.

## Components

| Component | Path | Description |
|---|---|---|
| OpenSearch domain | `terraform/opensearch/` | Shared VPC-only OpenSearch cluster |

## Consumers

| Repo | What it writes |
|---|---|
| [o11y-cloudfront-batch](https://github.com/NASA-PDS/o11y-cloudfront-batch) | Parsed PDS node access logs (ECS v8) |
| [o11y-cloudfront-streaming](https://github.com/NASA-PDS/o11y-cloudfront-streaming) | CloudFront real-time log stream |

## First deployment

All deployments are driven by Terragrunt from `cds-infra-deploy`. The phases below must run in order; phases marked **(parallel)** can run simultaneously.

All commands run from a checkout of `cds-infra-deploy` using: `task plan VENUE=<venue> COMPONENT=<component>` and `task apply VENUE=<venue> COMPONENT=<component>`.

| Phase | What | Repo | IAM tier required | Verify / test |
|---|---|---|---|---|
| **1** | Bootstrap OpenSearch (consumers disabled) | [o11y-platform `terraform/opensearch/`](terraform/README.md) | PowerUser | [OpenSearch smoke test](terraform/opensearch/README.md#smoke-test) |
| **2a** *(parallel with 2b)* | Batch IAM policies | [o11y-cloudfront-batch `terraform/iam/policies/`](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/terraform/README.md) | Admin (`iam:CreatePolicy`) | Apply succeeds; Logstash role and policy appear in SSM |
| **2b** *(parallel with 2a)* | Streaming IAM roles | [o11y-cloudfront-streaming `terraform/iam/`](https://github.com/NASA-PDS/o11y-cloudfront-streaming/blob/main/terraform/iam/README.md) | Admin (`iam:CreateRole`) | - |
| **2c** | CloudFront real-time log config + cache behaviors | [pdc-cds-infra `terraform/cloudfront/pds-main/`](https://github.com/NASA-PDS/pdc-cds-infra) | Platform Engineer (`iam:PassRole`) | - |
| **2d** *(parallel with 2c)* | Batch S3 + Logstash EC2 | [o11y-cloudfront-batch `terraform/s3/` + `terraform/logstash/`](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/terraform/README.md) | PowerUser / Platform Engineer (`iam:PassRole`) | [Verify the Logstash deployment](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/terraform/logstash/README.md#verify-the-deployment) (`smoke-test.sh`); pipeline tests: [`tests/README.md`](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/tests/README.md) |
| **3** | Streaming Kinesis/Firehose/Lambda + re-apply OpenSearch with consumers enabled | [o11y-cloudfront-streaming `terraform/streaming/`](https://github.com/NASA-PDS/o11y-cloudfront-streaming/blob/main/terraform/README.md) + [o11y-platform](terraform/README.md) | Platform Engineer (`iam:PassRole`) / PowerUser | - |
| **4** | OpenSearch UI Application (manual) | [o11y-platform](terraform/README.md#opensearch-ui-application) | PowerUser | [OpenSearch UI verification](terraform/README.md#opensearch-ui-application) |

Each phase publishes its outputs to SSM; the next phase reads them at plan time. Exception: Phase 2b requires a one-time `aws ssm put-parameter` seed for `/pds/pdc-cds-infra/s3/pds-logs-bucket-arn` — see [`terraform/README.md`](terraform/README.md#phase-2b) for details.

See [`terraform/README.md`](terraform/README.md) for full deploy and upgrade instructions.

### Operating and testing the batch Logstash

The Logstash EC2 is operated from the o11y-cloudfront-batch repo. Start with its
[Operations Runbook](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/docs/operations.md) (deploy, monitor, troubleshoot) and
[Access model](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/terraform/logstash/README.md#access-model) (bastion, then SSH as `pdsops`).

## Infrastructure

See [`terraform/README.md`](terraform/README.md) for deployment steps and Terraform module details.
