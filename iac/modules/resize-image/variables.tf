variable "aws_region" {
  description = "AWS region to deploy the resources"
  type        = string
  default     = "us-east-1"
}

variable "lambda_architecture" {
  description = "Instruction set architecture for your Lambda function. Valid values are 'x86_64' 'arm64'. Since we are also deploying the image via local deployemnt this should correspond to your computer architecture"
  type        = string
  default     = "arm64"
}

variable "query_language" {
  description = "Query Language to use in the Step Functions"
  type        = string
  default     = "jsonpath"

  validation {
    condition     = contains(["jsonata", "jsonpath"], var.query_language)
    error_message = "Valid values for var: test_variable are: 'jsonata', 'jsonpath'"
  }
}