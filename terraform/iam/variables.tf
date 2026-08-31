variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "us-west-2"
}

variable "partition" {
  type        = string
  description = "AWS partition (aws, aws-us-gov, aws-cn)"
  default     = "aws"
}

variable "domain_name" {
  type        = string
  description = "OpenSearch domain name — used to name the IAM role ${domain_name}-opensearch-cognito"
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
  default     = "terraform"
}

variable "managedby" {
  type        = string
  description = "Tag value for owner managing the resource"
}
