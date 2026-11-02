mock_provider "aws" {
  mock_data "aws_ssm_parameter" {
    defaults = {
      insecure_value = "internal.example.org"
    }
  }
}

variables {
  domain_name    = "test-domain"
  ebs_volume_gb  = 10
  managedby      = "team@example.org"
  venue          = "dev"
  vpc_enabled    = true
  vpc_id         = "vpc-0123456789abcdef0"
  vpc_subnet_ids = ["subnet-0123456789abcdef0"]
}

run "custom_endpoint_is_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_route53_record.opensearch_custom_endpoint) == 0
    error_message = "No DNS record may be created while custom_endpoint_enabled is false."
  }

  assert {
    condition     = length(data.aws_ssm_parameter.private_zone_id) == 0 && length(data.aws_ssm_parameter.private_zone_name) == 0
    error_message = "The private zone parameters must not be read while custom_endpoint_enabled is false."
  }

  assert {
    condition     = output.opensearch_custom_endpoint == null
    error_message = "opensearch_custom_endpoint must be null while custom_endpoint_enabled is false."
  }
}

run "custom_endpoint_creates_cname_in_private_zone" {
  command = plan

  variables {
    custom_endpoint_enabled         = true
    custom_endpoint_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = aws_route53_record.opensearch_custom_endpoint[0].name == "o11y-opensearch.internal.example.org" && aws_route53_record.opensearch_custom_endpoint[0].type == "CNAME"
    error_message = "The CNAME must be <custom_endpoint_label>.<private zone name>."
  }

  assert {
    condition     = one(aws_opensearch_domain.this.domain_endpoint_options).custom_endpoint_enabled == true && one(aws_opensearch_domain.this.domain_endpoint_options).custom_endpoint == "o11y-opensearch.internal.example.org"
    error_message = "The domain must use the custom hostname as its custom endpoint."
  }

  assert {
    condition     = one(aws_opensearch_domain.this.domain_endpoint_options).custom_endpoint_certificate_arn == "arn:aws:acm:us-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"
    error_message = "The domain must use the supplied ACM certificate."
  }

  assert {
    condition     = one(aws_opensearch_domain.this.domain_endpoint_options).enforce_https == true
    error_message = "HTTPS must stay enforced."
  }
}

run "ssm_endpoint_is_the_generated_one_until_published" {
  command = apply

  variables {
    custom_endpoint_enabled         = true
    custom_endpoint_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = aws_ssm_parameter.opensearch_endpoint.value != "o11y-opensearch.internal.example.org"
    error_message = "Consumers must keep the generated endpoint until publish_custom_endpoint_to_ssm is true."
  }
}

run "ssm_endpoint_is_the_custom_hostname_once_published" {
  command = plan

  variables {
    custom_endpoint_enabled         = true
    custom_endpoint_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"
    publish_custom_endpoint_to_ssm  = true
  }

  assert {
    condition     = aws_ssm_parameter.opensearch_endpoint.value == "o11y-opensearch.internal.example.org"
    error_message = "The custom hostname must be published to the endpoint parameter."
  }
}

run "label_is_configurable" {
  command = plan

  variables {
    custom_endpoint_enabled         = true
    custom_endpoint_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"
    custom_endpoint_label           = "search"
  }

  assert {
    condition     = output.opensearch_custom_endpoint == "search.internal.example.org"
    error_message = "custom_endpoint_label must set the first label of the hostname."
  }
}

run "custom_endpoint_without_certificate_is_rejected" {
  command = plan

  variables {
    custom_endpoint_enabled = true
  }

  expect_failures = [var.custom_endpoint_certificate_arn]
}

run "publishing_without_custom_endpoint_is_rejected" {
  command = plan

  variables {
    publish_custom_endpoint_to_ssm = true
  }

  expect_failures = [var.publish_custom_endpoint_to_ssm]
}
