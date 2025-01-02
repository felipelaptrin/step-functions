variable "aws_region" {
  description = "AWS region to deploy the resources"
  type        = string
  default     = "us-east-1"
}

variable "email" {
  description = "Email to subscribe in the SNS topic"
  type        = string
}
