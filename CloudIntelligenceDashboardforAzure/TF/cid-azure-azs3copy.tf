# This Terraform Template deploys the Cloud Intelligence Dashboard for Azure

### Create a Resource Group for Terraform deployed resources
resource "aws_resourcegroups_group" "ResourceGroup" {
  name        = format("%s%s%s%s", var.PrefixCode, "rgg", var.EnvironmentCode, "cidazure")
  description = "Cloud Intelligence Dashboard for Azure resources"

  resource_query {
    query = <<JSON
{
  "ResourceTypeFilters": [
    "AWS::AllSupported"
  ],
  "TagFilters": [
    {
      "Key": "Provisioner",
      "Values": ["Terraform"]
    },
    {
      "Key": "Owner",
      "Values": ["${var.OwnerTag}"]
    },
    {
      "Key": "Environment",
      "Values": ["${var.EnvironmentTag}"]
    },
    {
      "Key": "Solution",
      "Values": ["cidazure"]
    }
  ]
}
JSON
  }

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "rgg", var.EnvironmentCode, "cidazure")
    rtype = "scaffold"
  }
}

resource "aws_secretsmanager_secret" "SecretsManagerSecret" {
  name        = format("%s%s%s%s", var.PrefixCode, "sms", var.EnvironmentCode, "cidazure")
  description = "Cloud Intelligence Dashboard for Azure Secrets"
  kms_key_id  = aws_kms_key.KMSKey.arn
  # Consider setting recovery_window_in_days to 7 in production
  recovery_window_in_days = 0

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "sms", var.EnvironmentCode, "cidazure")
    rtype = "security"
  }
}

# NOTE: Comment out these lines if deploying Azure Example
resource "aws_secretsmanager_secret_version" "SecretsManagerSecret" {
  secret_id = aws_secretsmanager_secret.SecretsManagerSecret.id
  secret_string = jsonencode({
    bloburl     = var.AzureBlobURL
    tenantid    = var.AzureTenantID
    appid       = var.AzureApplicationID
    appsecret   = var.AzureSecretKey
    bucket_name = "${aws_s3_bucket.S3Bucket.bucket}"
    isactive    = "True"
    begindate   = var.BlobToS3SyncStartDate
    sns_arn_l1  = "${aws_sns_topic.SNSTopicL1L2.arn}"
    sns_arn_l2  = "${aws_sns_topic.SNSTopicL2L3.arn}"
    sns_arn_l3  = "${aws_sns_topic.SNSTopicLargeFileInit.arn}"
    sns_arn_l4  = "${aws_sns_topic.SNSTopicLargeFilePart.arn}"
    sns_arn_l5  = "${aws_sns_topic.SNSTopicLargeFileRecomb.arn}"
  })
}

## NOTE: Uncomment these lines if deploying Azure Example
# resource "aws_secretsmanager_secret_version" "SecretsManagerSecret" {
#   secret_id = aws_secretsmanager_secret.SecretsManagerSecret.id
#   secret_string = jsonencode({
#     bloburl     = azurerm_storage_account.StorageAccount.primary_blob_endpoint
#     tenantid    = data.azurerm_client_config.current.tenant_id
#     appid       = azuread_application.AppRegistration.application_id
#     appsecret   = azuread_application_password.AppPassword.value
#     bucket_name = "${aws_s3_bucket.S3Bucket.bucket}"
#     isactive    = "True"
#     begindate   = var.BlobToS3SyncStartDate
#     sns_arn_l1  = "${aws_sns_topic.SNSTopicL1L2.arn}"
#     sns_arn_l2  = "${aws_sns_topic.SNSTopicL2L3.arn}"
#     sns_arn_l3  = "${aws_sns_topic.SNSTopicLargeFileInit.arn}"
#     sns_arn_l4  = "${aws_sns_topic.SNSTopicLargeFilePart.arn}"
#     sns_arn_l5  = "${aws_sns_topic.SNSTopicLargeFileRecomb.arn}"
#   })
# }

### Create KMS key
resource "aws_kms_key" "KMSKey" {
  deletion_window_in_days = 7
  description             = "Cloud Intelligence Dashboard for Azure KMS Key"
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.azurecidkms.json

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "kms", var.EnvironmentCode, "cidazure")
    rtype = "security"
  }
}

resource "aws_kms_alias" "KMSKeyAlias" {
  name          = format("%s%s%s%s%s", "alias/", var.PrefixCode, "kms", var.EnvironmentCode, "cidazure")
  target_key_id = aws_kms_key.KMSKey.key_id
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "azurecidkms" {
  statement {
    # https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-overview.html
    sid    = "Enable IAM User Permissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions = [
      "kms*"
    ]
    resources = [
      "*"
    ]
  }
  statement {
    # https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html
    sid    = "Enable Cloudwatch access to KMS Key"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${var.Region}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = [
      "*"
    ]
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:aws:logs:${var.Region}:${data.aws_caller_identity.current.account_id}:*"
      ]
    }
  }
}

### Create S3 bucket to receive data
resource "aws_s3_bucket" "S3Bucket" {
  # Add static bucket name if required
  # bucket      = format("%s%s%s%s", var.PrefixCode, "sss", var.EnvironmentCode, "cidazure")
  bucket_prefix = format("%s%s%s%s", var.PrefixCode, "sss", var.EnvironmentCode, "cidazure")
  # Consider changing force_destroy to 'false' in production environments
  force_destroy = true

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "sss", var.EnvironmentCode, "cidazure"),
    rtype = "storage"
  }
}

resource "aws_s3_bucket_policy" "S3Bucket" {
  bucket = aws_s3_bucket.S3Bucket.id
  policy = data.aws_iam_policy_document.S3Bucket.json
}

data "aws_iam_policy_document" "S3Bucket" {
  statement {
    sid    = "Allow HTTPS only"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
      "s3*"
    ]
    resources = [
      "${aws_s3_bucket.S3Bucket.arn}",
      "${aws_s3_bucket.S3Bucket.arn}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values = [
        "false"
      ]
    }
  }

  statement {
    sid    = "Allow TLS 1.2 and above"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
      "s3*"
    ]
    resources = [
      "${aws_s3_bucket.S3Bucket.arn}",
      "${aws_s3_bucket.S3Bucket.arn}/*"
    ]
    condition {
      test     = "NumericLessThan"
      variable = "s3:TlsVersion"
      values = [
        "1.2"
      ]
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "S3Bucket" {
  bucket = aws_s3_bucket.S3Bucket.bucket

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_alias.KMSKeyAlias.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_versioning" "S3Bucket" {
  bucket = aws_s3_bucket.S3Bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "S3Bucket" {
  bucket                  = aws_s3_bucket.S3Bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "LambdaIAM" {
  name        = format("%s%s%s%s", var.PrefixCode, "iar", var.EnvironmentCode, "cidazurelambda")
  description = "Cloud Intelligence Dashboard for Azure IAM role for Lambda Functions"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "iar", var.EnvironmentCode, "cidazurelambda")
    rtype = "security"
  }
}

resource "aws_iam_role_policy" "LambdaIAM" {
  name  = format("%s%s%s%s", var.PrefixCode, "irp", var.EnvironmentCode, "cidazurelambdas3")
  role  = aws_iam_role.LambdaIAM.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:GetObjectAcl",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload",
          "s3:CreateBucket",
          "s3:Put*"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.S3Bucket.arn}",
          "${aws_s3_bucket.S3Bucket.arn}/*"
        ]
      },
      {
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_kms_key.KMSKey.arn}"
        ]
      },
      {
        Action = [
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds",
          "secretsmanager:UpdateSecret"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_secretsmanager_secret.SecretsManagerSecret.arn}"
        ]
      },
      {
        Action = [
          "SNS:Publish"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_sns_topic.SNSTopicL1L2.arn}",
          "${aws_sns_topic.SNSTopicL2L3.arn}",
          "${aws_sns_topic.SNSTopicLargeFileInit.arn}",
          "${aws_sns_topic.SNSTopicLargeFilePart.arn}",
          "${aws_sns_topic.SNSTopicLargeFileRecomb.arn}",
          "${aws_sns_topic.SNSTopicDeadLetterQueue.arn}"
        ]
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:logs:${var.Region}:${data.aws_caller_identity.current.account_id}:log-group:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "EventBridgeIAM" {
  name        = format("%s%s%s%s", var.PrefixCode, "iar", var.EnvironmentCode, "cidazureeventbrg")
  description = "Cloud Intelligence Dashboard IAM role for EventBridge Schedule"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "events.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name  = format("%s%s%s%s", var.Region, "iar", var.EnvironmentCode, "cidazureeventbrg")
    rtype = "security"
  }
}

resource "aws_iam_role_policy" "EventBridgeIAM" {
  name  = format("%s%s%s%s", var.PrefixCode, "irp", var.EnvironmentCode, "cidazureeventbrg")
  role  = aws_iam_role.EventBridgeIAM.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "events:PutEvents"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:events:${var.Region}:${data.aws_caller_identity.current.account_id}:event-bus/*"
        ]
      }
    ]
  })
}

resource "aws_lambda_layer_version" "azure-arm-identity" {
  filename                 = "../CFN/azure-arm-identity.zip"
  layer_name               = "azure-arm-identity"
  compatible_runtimes      = ["python3.9"]
  compatible_architectures = ["arm64"]
}

resource "aws_lambda_layer_version" "azure-arm-storage" {
  filename                 = "../CFN/azure-arm-storage.zip"
  layer_name               = "azure-arm-storage"
  compatible_runtimes      = ["python3.9"]
  compatible_architectures = ["arm64"]
}

resource "aws_lambda_function" "LambdaFunction01" {
  filename                       = "../CFN/cid-azure-lambda01.zip"
  function_name                  = format("%s%s%s%s", var.PrefixCode, "lmd", var.EnvironmentCode, "cidazurelambda01")
  description                    = "Cloud Intelligence Dashboard for Azure Lambda01 (blobcopy-launch-qualification)"
  architectures                  = ["arm64"]
  handler                        = "blobcopy-launch-qualification.lambda_handler"
  kms_key_arn                    = aws_kms_key.KMSKey.arn
  role                           = aws_iam_role.LambdaIAM.arn
  runtime                        = "python3.9"
  memory_size                    = 128
  timeout                        = 90
  reserved_concurrent_executions = 1

  environment {
    variables = {
      secret               = aws_secretsmanager_secret.SecretsManagerSecret.arn
      partitionSize        = var.PartitionSize
      maxPartitionsPerFile = var.MaxPartitionsPerFile
      UseFullFilePath      = var.UseFullFilePath
      resourcePrefix       = var.PrefixCode
    }
  }
  ephemeral_storage {
    size = 512
  }
  dead_letter_config {
    target_arn = aws_sns_topic.SNSTopicDeadLetterQueue.arn
  }
  tracing_config {
    mode = "Active"
  }

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "lmd", var.EnvironmentCode, "cidazurelambda01")
    rtype = "compute"
  }

  # Ensures the partition size is not overwritten with subsequent applies
  lifecycle {
    ignore_changes = [environment[0].variables["partitionSize"]]
  }
}

resource "aws_lambda_function" "LambdaFunction02" {
  filename                       = "../CFN/cid-azure-lambda02.zip"
  function_name                  = format("%s%s%s%s", var.PrefixCode, "lmd", var.EnvironmentCode, "cidazurelambda02")
  description                    = "Cloud Intelligence Dashboard for Azure Lambda02 (blobcopy-find-blobs)"
  architectures                  = ["arm64"]
  handler                        = "blobcopy-find-blobs.lambda_handler"
  kms_key_arn                    = aws_kms_key.KMSKey.arn
  layers                         = [aws_lambda_layer_version.azure-arm-identity.arn, aws_lambda_layer_version.azure-arm-storage.arn]
  role                           = aws_iam_role.LambdaIAM.arn
  runtime                        = "python3.9"
  memory_size                    = 2560
  timeout                        = 900
  reserved_concurrent_executions = 1

  ephemeral_storage {
    size = 512
  }
  dead_letter_config {
    target_arn = aws_sns_topic.SNSTopicDeadLetterQueue.arn
  }
  tracing_config {
    mode = "Active"
  }

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "lmd", var.EnvironmentCode, "cidazurelambda02")
    rtype = "compute"
  }
}

resource "aws_lambda_function" "LambdaFunction03" {
  filename      = "../CFN/cid-azure-lambda03.zip"
  function_name = format("%s%s%s%s", var.PrefixCode, "lmd", var.EnvironmentCode, "cidazurelambda03")
  description   = "Cloud Intelligence Dashboard for Azure Lambda03 (blobcopy-download)"
  architectures = ["arm64"]
  handler       = "blobcopy-download.lambda_handler"
  kms_key_arn   = aws_kms_key.KMSKey.arn
  layers        = [aws_lambda_layer_version.azure-arm-identity.arn, aws_lambda_layer_version.azure-arm-storage.arn]
  role          = aws_iam_role.LambdaIAM.arn
  runtime       = "python3.9"
  memory_size   = 5120
  timeout       = 900

  ephemeral_storage {
    size = 5120
  }
  dead_letter_config {
    target_arn = aws_sns_topic.SNSTopicDeadLetterQueue.arn
  }
  tracing_config {
    mode = "Active"
  }

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "lmd", var.EnvironmentCode, "cidazurelambda03")
    rtype = "compute"
  }
}

resource "aws_lambda_function" "LambdaFunction04" {
  filename      = "../CFN/cid-azure-lambda04.zip"
  function_name = format("%s%s%s%s", var.PrefixCode, "lmd", var.EnvironmentCode, "cidazurelambda04")
  description   = "Cloud Intelligence Dashboard for Azure Lambda04 (blobcopy-largefile-initializer)"
  architectures = ["arm64"]
  handler       = "blobcopy-large-file-initiator.lambda_handler"
  kms_key_arn   = aws_kms_key.KMSKey.arn
  role          = aws_iam_role.LambdaIAM.arn
  runtime       = "python3.9"
  memory_size   = 1024
  timeout       = 900

  ephemeral_storage {
    size = 512
  }
  dead_letter_config {
    target_arn = aws_sns_topic.SNSTopicDeadLetterQueue.arn
  }
  tracing_config {
    mode = "Active"
  }

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "lmd", var.EnvironmentCode, "cidazurelambda04")
    rtype = "compute"
  }
}

resource "aws_lambda_function" "LambdaFunction05" {
  filename      = "../CFN/cid-azure-lambda05.zip"
  function_name = format("%s%s%s%s", var.PrefixCode, "lmd", var.EnvironmentCode, "cidazurelambda05")
  description   = "Cloud Intelligence Dashboard for Azure Lambda05 (blobcopy-largefile-parter)"
  architectures = ["arm64"]
  handler       = "blobcopy-large-file-part.lambda_handler"
  kms_key_arn   = aws_kms_key.KMSKey.arn
  layers        = [aws_lambda_layer_version.azure-arm-identity.arn, aws_lambda_layer_version.azure-arm-storage.arn]
  role          = aws_iam_role.LambdaIAM.arn
  runtime       = "python3.9"
  memory_size   = 2056
  timeout       = 900

  ephemeral_storage {
    size = 512
  }
  dead_letter_config {
    target_arn = aws_sns_topic.SNSTopicDeadLetterQueue.arn
  }
  tracing_config {
    mode = "Active"
  }

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "lmd", var.EnvironmentCode, "cidazurelambda05")
    rtype = "compute"
  }
}

resource "aws_lambda_function" "LambdaFunction06" {
  filename      = "../CFN/cid-azure-lambda06.zip"
  function_name = format("%s%s%s%s", var.PrefixCode, "lmd", var.EnvironmentCode, "cidazurelambda06")
  description   = "Cloud Intelligence Dashboard for Azure Lambda06 (blobcopy-largefile-recombinater)"
  architectures = ["arm64"]
  handler       = "blobcopy-large-file-recombinator.lambda_handler"
  kms_key_arn   = aws_kms_key.KMSKey.arn
  role          = aws_iam_role.LambdaIAM.arn
  runtime       = "python3.9"
  memory_size   = 1024
  timeout       = 900

  ephemeral_storage {
    size = 512
  }
  dead_letter_config {
    target_arn = aws_sns_topic.SNSTopicDeadLetterQueue.arn
  }
  tracing_config {
    mode = "Active"
  }

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "lmd", var.EnvironmentCode, "cidazurelambda05")
    rtype = "compute"
  }
}

resource "aws_sns_topic" "SNSTopicL1L2" {
  name              = format("%s%s%s%s", var.PrefixCode, "sns", var.EnvironmentCode, "cidazureL1_to_L2")
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "sns", var.EnvironmentCode, "cidazureL1_to_L2")
    rtype = "messaging"
  }
}

resource "aws_sns_topic" "SNSTopicL2L3" {
  name              = format("%s%s%s%s", var.PrefixCode, "sns", var.EnvironmentCode, "cidazureL2_to_L3")
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "sns", var.EnvironmentCode, "cidazureL2_to_L3")
    rtype = "messaging"
  }
}

resource "aws_sns_topic" "SNSTopicLargeFileInit" {
  name              = format("%s%s%s%s", var.PrefixCode, "sns", var.EnvironmentCode, "cidazureLargeFileInit")
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "sns", var.EnvironmentCode, "cidazureLargeFileInit")
    rtype = "messaging"
  }
}

resource "aws_sns_topic" "SNSTopicLargeFilePart" {
  name              = format("%s%s%s%s", var.PrefixCode, "sns", var.EnvironmentCode, "cidazureLargeFilePart")
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "sns", var.EnvironmentCode, "cidazureLargeFilePart")
    rtype = "messaging"
  }
}

resource "aws_sns_topic" "SNSTopicLargeFileRecomb" {
  name              = format("%s%s%s%s", var.PrefixCode, "sns", var.EnvironmentCode, "cidazureLargeFileRecomb")
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "sns", var.EnvironmentCode, "cidazureLargeFileRecomb")
    rtype = "messaging"
  }
}

resource "aws_sns_topic" "SNSTopicDeadLetterQueue" {
  name              = format("%s%s%s%s", var.PrefixCode, "sns", var.EnvironmentCode, "cidazureDLQ")
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "sns", var.EnvironmentCode, "cidazureDLQ")
    rtype = "messaging"
  }
}

resource "aws_sns_topic_subscription" "SNSSubscriptionL1L2" {
  topic_arn = aws_sns_topic.SNSTopicL1L2.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.LambdaFunction02.arn
}

resource "aws_sns_topic_subscription" "SNSSubscriptionL2L3" {
  topic_arn = aws_sns_topic.SNSTopicL2L3.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.LambdaFunction03.arn
}

resource "aws_sns_topic_subscription" "SNSSubscriptionLargeFileInit" {
  topic_arn = aws_sns_topic.SNSTopicLargeFileInit.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.LambdaFunction04.arn
}

resource "aws_sns_topic_subscription" "SNSSubscriptionLargeFilePart" {
  topic_arn = aws_sns_topic.SNSTopicLargeFilePart.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.LambdaFunction05.arn
}

resource "aws_sns_topic_subscription" "SNSSubscriptionLargeFileRecomb" {
  topic_arn = aws_sns_topic.SNSTopicLargeFileRecomb.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.LambdaFunction06.arn
}

resource "aws_lambda_permission" "LambdaPermissionL1L2" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.LambdaFunction02.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.SNSTopicL1L2.arn
}

resource "aws_lambda_permission" "LambdaPermissionL2L3" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.LambdaFunction03.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.SNSTopicL2L3.arn
}

resource "aws_lambda_permission" "LambdaPermissionLargeFileInit" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.LambdaFunction04.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.SNSTopicLargeFileInit.arn
}

resource "aws_lambda_permission" "LambdaPermissionLargeFilePart" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.LambdaFunction05.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.SNSTopicLargeFilePart.arn
}

resource "aws_lambda_permission" "LambdaPermissionLargeFileRecomb" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.LambdaFunction06.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.SNSTopicLargeFileRecomb.arn
}

resource "aws_cloudwatch_event_rule" "ScheduledRule" {
  name                = format("%s%s%s%s", var.PrefixCode, "evr", var.EnvironmentCode, "cidazure")
  description         = "Cloud Intelligence Dashboard for Azure Scheduled pull from Azure blob storage"
  state               = "ENABLED"
  role_arn            = aws_iam_role.EventBridgeIAM.arn
  schedule_expression = var.AzureCopySchedule

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "evr", var.EnvironmentCode, "cidazure")
    rtype = "messaging"
  }
}

resource "aws_cloudwatch_event_target" "ScheduledRule" {
  rule  = aws_cloudwatch_event_rule.ScheduledRule.name
  arn   = aws_lambda_function.LambdaFunction01.arn
}

resource "aws_lambda_permission" "LambdaPermissionScheduledRule" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.LambdaFunction01.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ScheduledRule.arn
}

resource "aws_cloudwatch_dashboard" "CloudwatchDashboard" {
  dashboard_name = format("%s%s%s%s", var.PrefixCode, "cwd", var.EnvironmentCode, "cidazure")
  dashboard_body = <<EOF
  {
    "widgets": [
      {
        "type": "metric",
        "width": 24,
        "height": 3,
        "x": 0,
        "y": 0,
        "properties": {
          "metrics": [
            [ "AWS/Lambda", "Invocations", "FunctionName", "${aws_lambda_function.LambdaFunction01.function_name}", { "id": "m1" } ],
            [ "AWS/Lambda", "Invocations", "FunctionName", "${aws_lambda_function.LambdaFunction02.function_name}", { "id": "m2" } ],
            [ "AWS/Lambda", "Invocations", "FunctionName", "${aws_lambda_function.LambdaFunction03.function_name}", { "id": "m3" } ],
            [ "AWS/Lambda", "Invocations", "FunctionName", "${aws_lambda_function.LambdaFunction04.function_name}", { "id": "m4" } ],
            [ "AWS/Lambda", "Invocations", "FunctionName", "${aws_lambda_function.LambdaFunction05.function_name}", { "id": "m5" } ],
            [ "AWS/Lambda", "Invocations", "FunctionName", "${aws_lambda_function.LambdaFunction06.function_name}", { "id": "m6" } ]
          ],
          "legend": {
              "position": "bottom"
          },
          "period": 300,
          "view": "singleValue",
          "stacked": true,
          "title": "Lambda Invocations",
          "stat": "Sum",
          "liveData": true,
          "sparkline": true,
          "trend": true,
          "setPeriodToTimeRange": true,
          "region": "${var.Region}"
        }
      },
      {
        "type": "metric",
        "width": 24,
        "height": 3,
        "x": 0,
        "y": 1,
        "properties": {
          "metrics": [
            [ "AWS/Lambda", "Errors", "FunctionName", "${aws_lambda_function.LambdaFunction01.function_name}", { "id": "m7" } ],
            [ "AWS/Lambda", "Errors", "FunctionName", "${aws_lambda_function.LambdaFunction02.function_name}", { "id": "m8" } ],
            [ "AWS/Lambda", "Errors", "FunctionName", "${aws_lambda_function.LambdaFunction03.function_name}", { "id": "m9" } ],
            [ "AWS/Lambda", "Errors", "FunctionName", "${aws_lambda_function.LambdaFunction04.function_name}", { "id": "m10" } ],
            [ "AWS/Lambda", "Errors", "FunctionName", "${aws_lambda_function.LambdaFunction05.function_name}", { "id": "m11" } ],
            [ "AWS/Lambda", "Errors", "FunctionName", "${aws_lambda_function.LambdaFunction06.function_name}", { "id": "m12" } ]
          ],
          "legend": {
              "position": "bottom"
          },
          "period": 300,
          "view": "singleValue",
          "stacked": false,
          "title": "Lambda Errors",
          "stat": "Sum",
          "liveData": true,
          "sparkline": true,
          "trend": true,
          "setPeriodToTimeRange": true,
          "region": "${var.Region}"
        }
      },
      {
        "type": "metric",
        "width": 24,
        "height": 3,
        "x": 0,
        "y": 2,
        "properties": {
          "metrics": [
            [ "AWS/Lambda", "Duration", "FunctionName", "${aws_lambda_function.LambdaFunction01.function_name}", { "id": "m13" } ],
            [ "AWS/Lambda", "Duration", "FunctionName", "${aws_lambda_function.LambdaFunction02.function_name}", { "id": "m14" } ],
            [ "AWS/Lambda", "Duration", "FunctionName", "${aws_lambda_function.LambdaFunction03.function_name}", { "id": "m15" } ],
            [ "AWS/Lambda", "Duration", "FunctionName", "${aws_lambda_function.LambdaFunction04.function_name}", { "id": "m16" } ],
            [ "AWS/Lambda", "Duration", "FunctionName", "${aws_lambda_function.LambdaFunction05.function_name}", { "id": "m17" } ],
            [ "AWS/Lambda", "Duration", "FunctionName", "${aws_lambda_function.LambdaFunction06.function_name}", { "id": "m18" } ]
          ],
          "legend": {
              "position": "bottom"
          },
          "period": 300,
          "view": "singleValue",
          "stacked": true,
          "title": "Lambda Duration",
          "stat": "p90",
          "liveData": true,
          "sparkline": true,
          "trend": true,
          "setPeriodToTimeRange": true,
          "region": "${var.Region}"
        }
      },
      {
        "type": "metric",
        "width": 24,
        "height": 6,
        "x": 0,
        "y": 3,
        "properties": {
          "metrics": [
            [ "AWS/Lambda", "Duration", "FunctionName", "${aws_lambda_function.LambdaFunction01.function_name}", { "id": "m19" } ],
            [ "AWS/Lambda", "Duration", "FunctionName", "${aws_lambda_function.LambdaFunction02.function_name}", { "id": "m20" } ],
            [ "AWS/Lambda", "Duration", "FunctionName", "${aws_lambda_function.LambdaFunction03.function_name}", { "id": "m21" } ],
            [ "AWS/Lambda", "Duration", "FunctionName", "${aws_lambda_function.LambdaFunction04.function_name}", { "id": "m22" } ],
            [ "AWS/Lambda", "Duration", "FunctionName", "${aws_lambda_function.LambdaFunction05.function_name}", { "id": "m23" } ],
            [ "AWS/Lambda", "Duration", "FunctionName", "${aws_lambda_function.LambdaFunction06.function_name}", { "id": "m24" } ]
          ],
          "legend": {
              "position": "bottom"
          },
          "period": 86400,
          "view": "timeSeries",
          "stacked": true,
          "title": "Lambda Duration Graph",
          "stat": "p90",
          "liveData": false,
          "trend": true,
          "setPeriodToTimeRange": true,
          "region": "${var.Region}"
        }
      },
      {
        "type": "metric",
        "width": 4,
        "height": 6,
        "x": 0,
        "y": 4,
        "properties": {
          "metrics": [
            [ "AWS/SNS", "NumberOfNotificationsFailed", "TopicName", "${aws_sns_topic.SNSTopicL1L2.name}", { "stat": "Sum", "id": "m10" } ],
            [ "AWS/SNS", "NumberOfNotificationsFailed", "TopicName", "${aws_sns_topic.SNSTopicL2L3.name}", { "stat": "Sum", "id": "m10" } ],
            [ "AWS/SNS", "NumberOfNotificationsFailed", "TopicName", "${aws_sns_topic.SNSTopicLargeFileInit.name}", { "stat": "Sum", "id": "m10" } ],
            [ "AWS/SNS", "NumberOfNotificationsFailed", "TopicName", "${aws_sns_topic.SNSTopicLargeFilePart.name}", { "stat": "Sum", "id": "m10" } ],
            [ "AWS/SNS", "NumberOfNotificationsFailed", "TopicName", "${aws_sns_topic.SNSTopicLargeFileRecomb.name}", { "stat": "Sum", "id": "m10" } ]
          ],
          "legend": {
              "position": "bottom"
          },
          "period": 300,
          "view": "singleValue",
          "stacked": true,
          "title": "SNS Errors",
          "stat": "p90",
          "liveData": true,
          "sparkline": true,
          "trend": true,
          "setPeriodToTimeRange": true,
          "region": "${var.Region}"
        }
      },
      {
        "type": "metric",
        "x": 6,
        "y": 4,
        "width": 20,
        "height": 6,
        "properties": {
          "view": "timeSeries",
          "stacked": false,
          "metrics": [
            [ "AWS/S3", "BucketSizeBytes", "StorageType", "StandardStorage", "BucketName", "${aws_s3_bucket.S3Bucket.bucket}", { "period": 86400 }]
          ],
          "setPeriodToTimeRange": false,
          "start": "-PT168H",
          "end": "PT0H",
          "region": "${var.Region}",
          "title": "S3 Storage",
          "yAxis": {
            "left": {
              "label": "Size(GB)"
            }
          }
        }
      },
      {
        "type": "log",
        "width": 24,
        "height": 9,
        "x": 0,
        "y": 5,
        "properties": {
          "query": "SOURCE '/aws/lambda/${aws_lambda_function.LambdaFunction01.function_name}' | SOURCE '/aws/lambda/${aws_lambda_function.LambdaFunction02.function_name}' | SOURCE '/aws/lambda/${aws_lambda_function.LambdaFunction03.function_name}' | SOURCE '/aws/lambda/${aws_lambda_function.LambdaFunction04.function_name}' | SOURCE '/aws/lambda/${aws_lambda_function.LambdaFunction05.function_name}' | SOURCE '/aws/lambda/${aws_lambda_function.LambdaFunction06.function_name}' | fields @timestamp, @log, @message | sort @timestamp desc | limit 300",
          "region": "${var.Region}",
          "title": "Lambda Trace",
          "view": "table"
        }
      },
      {
        "type": "log",
        "width": 24,
        "height": 3,
        "x": 0,
        "y": 6,
        "properties": {
          "query": "SOURCE '/aws/lambda/${aws_lambda_function.LambdaFunction01.function_name}' | fields @timestamp, @log, @message | filter @message LIKE /ERROR/ or @message LIKE /Task timed out/ | sort @timestamp desc | limit 10",
          "region": "${var.Region}",
          "title": "Lambda01 Errors",
          "view": "table"
        }
      },
      {
        "type": "log",
        "width": 24,
        "height": 3,
        "x": 0,
        "y": 7,
        "properties": {
          "query": "SOURCE '/aws/lambda/${aws_lambda_function.LambdaFunction02.function_name}' | fields @timestamp, @log, @message | filter @message LIKE /ERROR/ or @message LIKE /Task timed out/ | sort @timestamp desc | limit 10",
          "region": "${var.Region}",
          "title": "Lambda02 Errors",
          "view": "table"
        }
      },
      {
        "type": "log",
        "width": 24,
        "height": 3,
        "x": 0,
        "y": 8,
        "properties": {
          "query": "SOURCE '/aws/lambda/${aws_lambda_function.LambdaFunction03.function_name}' | fields @timestamp, @log, @message | filter @message LIKE /ERROR/ or @message LIKE /Task timed out/ | sort @timestamp desc | limit 10",
          "region": "${var.Region}",
          "title": "Lambda03 Errors",
          "view": "table"
        }
      },
      {
        "type": "log",
        "width": 24,
        "height": 3,
        "x": 0,
        "y": 9,
        "properties": {
          "query": "SOURCE '/aws/lambda/${aws_lambda_function.LambdaFunction04.function_name}' | fields @timestamp, @log, @message | filter @message LIKE /ERROR/ or @message LIKE /Task timed out/ | sort @timestamp desc | limit 10",
          "region": "${var.Region}",
          "title": "Lambda04 Errors",
          "view": "table"
        }
      },
      {
        "type": "log",
        "width": 24,
        "height": 3,
        "x": 0,
        "y": 10,
        "properties": {
          "query": "SOURCE '/aws/lambda/${aws_lambda_function.LambdaFunction05.function_name}' | fields @timestamp, @log, @message | filter @message LIKE /ERROR/ or @message LIKE /Task timed out/ | sort @timestamp desc | limit 10",
          "region": "${var.Region}",
          "title": "Lambda05 Errors",
          "view": "table"
        }
      },
      {
        "type": "log",
        "width": 24,
        "height": 3,
        "x": 0,
        "y": 11,
        "properties": {
          "query": "SOURCE '/aws/lambda/${aws_lambda_function.LambdaFunction06.function_name}' | fields @timestamp, @log, @message | filter @message LIKE /ERROR/ or @message LIKE /Task timed out/ | sort @timestamp desc | limit 10",
          "region": "${var.Region}",
          "title": "Lambda06 Errors",
          "view": "table"
        }
      }
    ]
  }
EOF
}