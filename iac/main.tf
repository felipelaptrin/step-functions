locals {
  project = "resize-profile-picture"
}

##############################
##### S3 + SQS
##############################
resource "aws_s3_bucket" "this" {
  bucket_prefix = "profile-pictures"
}

resource "aws_sqs_queue" "this" {
  name = "profile-pictures"
}

resource "aws_sqs_queue_policy" "this" {
  queue_url = aws_sqs_queue.this.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Id" : "AllowS3Notification",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "s3.amazonaws.com"
        },
        "Action" : [
          "SQS:SendMessage"
        ],
        "Resource" : aws_sqs_queue.this.arn,
        "Condition" : {
          "ArnLike" : {
            "aws:SourceArn" : aws_s3_bucket.this.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "this" {
  bucket = aws_s3_bucket.this.id

  queue {
    queue_arn     = aws_sqs_queue.this.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "uploaded/"
  }
}

##############################
##### DYNAMODB TABLE
##############################
resource "aws_dynamodb_table" "this" {
  name         = "user"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }
}

##############################
##### LAMBDA & ECR
##############################
resource "aws_ecr_repository" "this" {
  name                 = "${local.project}"
  image_tag_mutability = "MUTABLE"
}

resource "docker_image" "this" {
  name = "${aws_ecr_repository.this.repository_url}:latest"

  build {
    context  = "${path.cwd}/../lambda"
    platform = var.lambda_architecture == "arm64" ? "linux/arm64" : "linux/amd64"
  }
  force_remove = true
}

resource "docker_registry_image" "this" {
  name          = docker_image.this.name
  keep_remotely = false
}

resource "aws_lambda_function" "this" {
  depends_on = [docker_registry_image.this]

  function_name = local.project
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.this.repository_url}:latest"
  architectures = [var.lambda_architecture]
  timeout       = 10

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.this.id
    }
  }
}

resource "aws_iam_role" "lambda" {
  name = "lambda-${local.project}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name = "/aws/lambda/${local.project}"
}

resource "aws_iam_policy" "lambda" {
  name = "lambda-${local.project}"
  path = "/"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "S3Actions",
        Action = [
          "s3:List*",
          "s3:Get*",
          "s3:Put*",
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.this.arn}",
          "${aws_s3_bucket.this.arn}/*"
        ]
      },
      {
        Sid = "CloudWatchActions"
        Effect = "Allow",
        Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
    }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
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
        Sid = "S3Actions",
        Action = [
          "s3:List*",
          "s3:Get*",
          "s3:Put*",
          "s3:Delete*",
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.this.arn}",
          "${aws_s3_bucket.this.arn}/*"
        ]
      },
      {
        Sid = "LambdaActions",
        Action = [
          "lambda:InvokeFunction",
        ]
        Effect   = "Allow"
        Resource = [
          "${aws_lambda_function.this.arn}",
          "${aws_lambda_function.this.arn}*"
        ]
      },
      {
        Sid = "DynamoDBActions",
        Action = [
          "dynamodb:UpdateItem",
        ]
        Effect   = "Allow"
        Resource = "${aws_dynamodb_table.this.arn}"
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
    "machine-definition/definition.json",
    {
      LAMBDA_NAME         = aws_lambda_function.this.id
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.this.id
    }
  )
}

##############################
##### EVENTBRIDGE PIPE
##############################
resource "aws_iam_role" "pipe" {
  name = "pipe-${local.project}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "pipes.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "pipe" {
  name = "pipe-${local.project}"
  path = "/"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "SqsAccess",
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Effect   = "Allow"
        Resource = "${aws_sqs_queue.this.arn}"
      },
      {
        Sid = "StepFunctionsAccess",
        Action = [
          "states:StartExecution",
          "states:StartSyncExecution"
        ]
        Effect   = "Allow"
        Resource = "${aws_sfn_state_machine.this.arn}"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "pipe" {
  role       = aws_iam_role.pipe.name
  policy_arn = aws_iam_policy.pipe.arn
}

resource "aws_pipes_pipe" "this" {
  name     = "trigger-${local.project}-sfn"
  role_arn = aws_iam_role.pipe.arn
  source   = aws_sqs_queue.this.arn
  target   = aws_sfn_state_machine.this.arn

  source_parameters {
    sqs_queue_parameters {
      batch_size = 5
      maximum_batching_window_in_seconds = 5
    }
  }

  target_parameters {
    step_function_state_machine_parameters {
      invocation_type = "FIRE_AND_FORGET"
    }
  }
}