terraform {
  backend "s3" {
    key = "o11y-platform/iam.tfstate"
  }
}
