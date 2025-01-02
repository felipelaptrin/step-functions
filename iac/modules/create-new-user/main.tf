locals {
  project = "create-new-user"
}

##############################
##### IAM
##############################
resource "aws_iam_group" "developer" {
  name = "developers-group"
}

resource "aws_iam_group" "admin" {
  name = "admins-group"
}
##############################
##### SNS
##############################
resource "aws_sns_topic" "this" {
  name = local.project
}

resource "aws_sns_topic_subscription" "this" {
  topic_arn = aws_sns_topic.this.arn
  protocol  = "email"
  endpoint  = var.email
}

##############################
##### STEP FUNCTIONS
##############################
resource "aws_iam_role" "sfn" {
  name = "sfn-${local.project}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "states.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "sfn" {
  name = "sfn-${local.project}"
  path = "/"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "SnsActions",
        Action = [
          "sns:Publish",
        ]
        Effect = "Allow"
        Resource = aws_sns_topic.this.arn
      },
      {
        Sid = "IamActions",
        Action = [
          "iam:CreateUser",
          "iam:AddUserToGroup",
        ]
        Effect = "Allow"
        Resource = ["*"]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sfn" {
  role       = aws_iam_role.sfn.name
  policy_arn = aws_iam_policy.sfn.arn
}

resource "aws_sfn_state_machine" "this" {
  name     = "${local.project}"
  role_arn = aws_iam_role.sfn.arn
  definition = templatefile(
    "machine-definition/create-new-user/jsonata.json",
    {
      TOPIC_ARN = aws_sns_topic.this.arn
      ADMIN_GROUP_NAME = aws_iam_group.admin.name
      DEVELOP_GROUP_NAME = aws_iam_group.developer.name
    }
  )
}
