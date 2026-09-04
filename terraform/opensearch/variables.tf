variable "aws_region" {
  type        = string
  description = "Effective AWS Region"
  default     = "us-west-2"
}

variable "partition" {
  type        = string
  description = "AWS partition (aws, aws-us-gov, aws-cn)"
  default     = "aws"
}

variable "domain_name" {
  type        = string
  description = "Name of the managed OpenSearch domain"
}

variable "data_node_instance_type" {
  type        = string
  description = "Instance type for data nodes"
  default     = "r6g.xlarge.search"
}

variable "data_node_count" {
  type        = number
  description = "Number of data nodes"
  default     = 3
}

variable "master_node_instance_type" {
  type        = string
  description = "Instance type for dedicated master nodes"
  default     = "m6g.large.search"
}

variable "master_node_count" {
  type        = number
  description = "Number of dedicated master nodes"
  default     = 3
}

variable "dedicated_master_enabled" {
  type        = bool
  description = "Enable dedicated master nodes. Recommended for prod, unnecessary for dev single-node clusters."
  default     = true
}

variable "zone_awareness_enabled" {
  type        = bool
  description = "Enable zone awareness (multi-AZ). Set true for prod (3 nodes, 3 subnets), false for dev (1 node, 1 subnet)."
  default     = false
}

variable "availability_zone_count" {
  type        = number
  description = "Number of AZs for zone awareness. Must match data_node_count and number of vpc_subnet_ids. Only used when zone_awareness_enabled = true."
  default     = 3
}

variable "ebs_volume_gb" {
  type        = number
  description = "EBS volume size per data node in GB"
}

variable "ebs_volume_type" {
  type        = string
  description = "EBS volume type"
  default     = "gp3"
}

variable "node_to_node_encryption" {
  type        = bool
  description = "Enable node-to-node encryption"
  default     = true
}

variable "encryption_at_rest" {
  type        = bool
  description = "Enable encryption at rest"
  default     = true
}

variable "vpc_enabled" {
  type        = bool
  description = "Deploy the domain inside a VPC. This module is intended to be VPC-only."
  validation {
    condition     = var.vpc_enabled == true
    error_message = "vpc_enabled must be true — this module is VPC-only and does not support a public endpoint."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for the OpenSearch domain security group. Required when vpc_enabled = true."
  default     = ""
}

variable "vpc_subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the OpenSearch domain VPC endpoint. One subnet per AZ. Required when vpc_enabled = true."
  default     = []
}

variable "ec2_security_group_name" {
  type        = string
  description = "Name of the MCP EC2 security group. Used to allow 443 inbound to the OpenSearch domain. Required when vpc_enabled = true."
  default     = ""
}

variable "o11y_cloudfront_batch_enabled" {
  type        = bool
  description = "Whether the o11y-cloudfront-batch consumer has been deployed. When true, its Logstash EC2 role ARN is read from SSM (/pds/o11y-cloudfront-batch/iam/roles/ec2/instance-role-arn) and added as an OpenSearch access-policy principal. Leave false for the initial bootstrap deploy (before o11y-cloudfront-batch's iam/roles module has published that parameter), then re-apply with true once it exists — this only updates the access policy, no domain redeployment."
  default     = false
}

variable "o11y_cloudfront_streaming_enabled" {
  type        = bool
  description = "Whether the o11y-cloudfront-streaming consumer has been deployed. When true, its Firehose role ARN is read from SSM (/pds/o11y-cloudfront-streaming/firehose/firehose-role-arn) and added as an OpenSearch access-policy principal, and its Firehose SG ID is read from SSM (/pds/o11y-cloudfront-streaming/firehose/firehose-security-group-id) to create the Firehose→OpenSearch VPC ingress rule. Leave false for the initial bootstrap deploy (before o11y-cloudfront-streaming has published those SSM parameters), then re-apply with true once it exists — this only updates the access policy and ingress rule, no domain redeployment."
  default     = false
}

variable "venue" {
  type        = string
  description = "Tag value for venue (dev, test, prod)"
}

variable "tenant" {
  type        = string
  description = "Tag value for tenant"
  default     = "en"
}

variable "component" {
  type        = string
  description = "Tag value for component"
  default     = "o11y-platform"
}

variable "cicd" {
  type        = string
  description = "Tag value for CICD deployment method"
  default     = "iac"
}

variable "managedby" {
  type        = string
  description = "Tag value for owner managing the resource (e.g. PDS Team email distro)"
}

variable "engine_version" {
  type        = string
  description = "OpenSearch engine version (e.g. OpenSearch_2.17). Pin to the deployed version to prevent unintended upgrades."
  default     = "OpenSearch_2.19"
}
