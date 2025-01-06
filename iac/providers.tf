provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project    = "Step Functions"
      Repository = "https://github.com/felipelaptrin/step-functions"
    }
  }
}


