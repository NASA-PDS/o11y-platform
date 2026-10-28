# Planetary Data Cloud (PDC) o11y-platform

Shared OpenSearch-backed observability platform for the Planetary Data Cloud. Aggregates logs from PDS services: batch node access logs via Logstash and CloudFront real-time logs via Kinesis Firehose.

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

OpenSearch is a shared platform: both o11y-cloudfront-batch and o11y-cloudfront-streaming write to it. Consumers discover the endpoint via SSM with no shared Terraform state between repos.

## Components

| Component | Path | Description |
|---|---|---|
| OpenSearch domain | `terraform/opensearch/` | Shared VPC-only OpenSearch cluster |

## Consumers

| Repo | What it writes |
|---|---|
| [o11y-cloudfront-batch](https://github.com/NASA-PDS/o11y-cloudfront-batch) | Parsed PDS node access logs (ECS v8) |
| [o11y-cloudfront-streaming](https://github.com/NASA-PDS/o11y-cloudfront-streaming) | CloudFront real-time log stream |

## Documentation map

Each topic has one home. Other docs link to it instead of repeating it.

| Topic | Home |
|---|---|
| Deployment order, permission tiers, cross-repo SSM contract | [Deployment runbook](terraform/README.md) |
| First deployment of a venue | [Initial deployment](terraform/README.md#initial-deployment) |
| Updating a deployed component | [Updating](terraform/README.md#updating) |
| Testing and verifying a deployment | [Testing](terraform/README.md#testing) |
| OpenSearch domain inputs, engine and node upgrades | [`terraform/opensearch/README.md`](terraform/opensearch/README.md) |
| Batch `iam`, `s3`, `logstash` modules | [o11y-cloudfront-batch `terraform/README.md`](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/terraform/README.md) |
| Operating and troubleshooting Logstash | [o11y-cloudfront-batch Operations Runbook](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/docs/operations.md) |
| Logstash pipeline tests | [o11y-cloudfront-batch `tests/README.md`](https://github.com/NASA-PDS/o11y-cloudfront-batch/blob/main/tests/README.md) |
| Streaming `iam/` and `streaming/` modules | [o11y-cloudfront-streaming `terraform/README.md`](https://github.com/NASA-PDS/o11y-cloudfront-streaming/blob/main/terraform/README.md) |
| CloudFront distribution and the o11y integration flags | [pdc-cds-infra `cloudfront/pds-main`](https://github.com/NASA-PDS/pdc-cds-infra/blob/main/terraform/cloudfront/pds-main/README.md) |
| Shared EC2, S3, and IAM Terraform modules | [pdc-tf-modules](https://github.com/NASA-PDS/pdc-tf-modules) |

## First deployment

Follow the [Initial deployment](terraform/README.md#initial-deployment) section of the deployment runbook. All deployments are driven by Terragrunt from `cds-infra-deploy`.
