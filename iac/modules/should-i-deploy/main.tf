locals {
  project = "should-i-deploy"
}

##############################
##### EVENTBRIDGE PIPE
##############################
resource "aws_iam_user" "deploy" {
  name = "terraform-deploy-from-pipeline"
}

resource "aws_iam_user_policy_attachment" "deploy" {
  user       = aws_iam_user.deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
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
        Sid = "IAMActions",
        Action = [
          "iam:AttachUserPolicy",
          "iam:DetachUserPolicy",
          "iam:ListAttachedUserPolicies"
        ]
        Effect   = "Allow"
        Resource = "${aws_iam_user.deploy.arn}"
      },
      {
        Sid = "InvokeHttpEndpoint"
        Action = "states:InvokeHTTPEndpoint"
        Effect = "Allow"
        Resource = "*"
      },
      {
        Sid = "EventBridgeActions"
        Action = "events:RetrieveConnectionCredentials"
        Effect = "Allow"
        Resource = "${aws_cloudwatch_event_connection.sfn.arn}"
      },
      {
        Sid = "SecretsActions"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue"
        ]
        Effect = "Allow"
        Resource = "${aws_cloudwatch_event_connection.sfn.secret_arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sfn" {
  role       = aws_iam_role.sfn.name
  policy_arn = aws_iam_policy.sfn.arn
}

resource "aws_cloudwatch_event_connection" "sfn" {
  name               = local.project
  description        = "A connection used in the ${local.project} Step Function"
  authorization_type = "BASIC"

  # This API does not require credential but it's a must to configure
  auth_parameters {
    basic {
      username = "fake"
      password = "fake"
    }
  }
}

resource "aws_sfn_state_machine" "this" {
  name     = "${local.project}"
  role_arn = aws_iam_role.sfn.arn
  definition = templatefile(
    "machine-definition/should-i-deploy/jsonata.json",
    {
      CONNECTION_ARN  = aws_cloudwatch_event_connection.sfn.arn
      DENY_POLICY_ARN = "arn:aws:iam::aws:policy/AWSDenyAll"
      IAM_USER_NAME   = aws_iam_user.deploy.name
    }
  )
}

##############################
##### EVENTBRIDGE
##############################
resource "aws_cloudwatch_event_rule" "this" {
  name                = local.project
  schedule_expression = var.frequency_in_minutes == 1 ? "rate(1 minute)" : "rate(${var.frequency_in_minutes} minutes)"
}

resource "aws_iam_role" "eventbridge" {
  name = "eventbridge-${local.project}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "events.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "eventbridge" {
  name = "eventbridge-${local.project}"
  path = "/"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "IAMActions",
        Action = [
          "states:StartExecution",
        ]
        Effect   = "Allow"
        Resource = "${aws_sfn_state_machine.this.arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eventbridge" {
  role       = aws_iam_role.eventbridge.name
  policy_arn = aws_iam_policy.eventbridge.arn
}

resource "aws_cloudwatch_event_target" "this" {
  rule      = aws_cloudwatch_event_rule.this.name
  target_id = "step-function-${local.project}"
  arn       = aws_sfn_state_machine.this.arn
  role_arn  = aws_iam_role.eventbridge.arn
}

