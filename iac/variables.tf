variable "aws_region" {
  description = "AWS region to deploy the resources"
  type        = string
  default     = "us-east-1"
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

variable "email" {
  description = "Email to subscribe in the SNS topic (create-new-user exercise)"
  type        = string
}