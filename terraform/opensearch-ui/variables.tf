variable "aws_region" {
  type        = string
  description = "Effective AWS Region"
  default     = "us-west-2"
}

variable "application_name" {
  type        = string
  description = "Name of the OpenSearch UI application (pds-<venue>-o11y-ui). Unique per account and Region; 3-30 characters, lowercase letters, numbers, and hyphens, starting with a letter."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,29}$", var.application_name))
    error_message = "application_name must be 3-30 characters of lowercase letters, numbers, and hyphens, starting with a letter."
  }
}

variable "admin_role_arns" {
  type        = list(string)
  description = "IAM role ARNs granted application admin on the OpenSearch UI application. Admins can edit and delete the application and create, edit, and delete workspaces; admin does not grant data access (see ops_role_arns in the opensearch module). Must be IAM role ARNs (arn:<partition>:iam::<account-id>:role/<name>), which match every session of the role; assumed-role/STS ARNs do not match. At least one is required."

  validation {
    condition     = length(var.admin_role_arns) > 0 && alltrue([for arn in var.admin_role_arns : can(regex("^arn:[a-z-]+:iam::[0-9]{12}:role/.+$", arn))])
    error_message = "admin_role_arns must contain at least one entry, and every entry must be an IAM role ARN of the form arn:<partition>:iam::<account-id>:role/<name>. Assumed-role (arn:...:sts::...) ARNs are not valid."
  }
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
