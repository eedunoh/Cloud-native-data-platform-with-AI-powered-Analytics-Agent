resource "aws_iam_role" "data_platform_server_role" {
  name = var.iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "data_platform_iam_policy" {
  name        = var.iam_policy_name
  description = "Data platform iam policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.streaming_bucket.arn}",
          "${aws_s3_bucket.streaming_bucket.arn}/*",

          "${aws_s3_bucket.batch_bucket.arn}",
          "${aws_s3_bucket.batch_bucket.arn}/*",

          "${aws_s3_bucket.policy_document_bucket.arn}",
          "${aws_s3_bucket.policy_document_bucket.arn}/*",

          "${aws_s3_bucket.document_extract_bucket.arn}",
          "${aws_s3_bucket.document_extract_bucket.arn}/*"
        ]
      },

      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParameterHistory"
        ]
        Resource = [
          "arn:aws:ssm:${var.region}:*:parameter/streaming_bucket",
          "arn:aws:ssm:${var.region}:*:parameter/batch_bucket",
          "arn:aws:ssm:${var.region}:*:parameter/policy_document_bucket",
          "arn:aws:ssm:${var.region}:*:parameter/document_extract_bucket"
        ]
      },

    ]
  })
}

resource "aws_iam_role_policy_attachment" "data_platform_policy_attachment" {
  role       = aws_iam_role.data_platform_server_role.name
  policy_arn = aws_iam_policy.data_platform_iam_policy.arn
}

resource "aws_iam_instance_profile" "data_platform_instance_profile" {
  name = var.instance_profile_name
  role = aws_iam_role.data_platform_server_role.name
}


# Output
output "data_platform_instance_profile" {
  value = aws_iam_instance_profile.data_platform_instance_profile.name
}