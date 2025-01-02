locals {
  project = "bucket-replication"
}

##############################
##### S3
##############################
resource "aws_s3_bucket" "source" {
  bucket_prefix = "source"
}

resource "aws_s3_bucket" "destination" {
  bucket_prefix = "destination"
}

##############################
##### DATA SYNC
##############################
resource "aws_iam_role" "datasync" {
  name = "datasync-${local.project}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "datasync.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "datasync" {
  name = "datasync-${local.project}"
  path = "/"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "S3Actions",
        Action = [
          "s3:Get*",
          "s3:List*",
          "s3:Put*",
          "s3:DeleteObject",
        ]
        Effect = "Allow"
        Resource = [
            aws_s3_bucket.source.arn,
            "${aws_s3_bucket.source.arn}/*",
            aws_s3_bucket.destination.arn,
            "${aws_s3_bucket.destination.arn}/*",
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "datasync" {
  role       = aws_iam_role.datasync.name
  policy_arn = aws_iam_policy.datasync.arn
}

resource "aws_datasync_location_s3" "source" {
  s3_bucket_arn = aws_s3_bucket.source.arn
  subdirectory  = ""

  s3_config {
    bucket_access_role_arn = aws_iam_role.datasync.arn
  }
}

resource "aws_datasync_location_s3" "destination" {
  s3_bucket_arn = aws_s3_bucket.destination.arn
  subdirectory  = ""

  s3_config {
    bucket_access_role_arn = aws_iam_role.datasync.arn
  }
}

resource "aws_datasync_task" "this" {
  destination_location_arn = aws_datasync_location_s3.destination.arn
  name                     = local.project
  source_location_arn      = aws_datasync_location_s3.source.arn

  options {
    posix_permissions = "NONE"
    uid = "NONE"
    gid = "NONE"
  }
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
          "datasync:StartTaskExecution",
          "datasync:DescribeTaskExecution",
        ]
        Effect = "Allow"
        Resource = "*"
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
    "machine-definition/bucket-replication/jsonata.json",
    {
      TASK_ARN = aws_datasync_task.this.arn
    }
  )
}
