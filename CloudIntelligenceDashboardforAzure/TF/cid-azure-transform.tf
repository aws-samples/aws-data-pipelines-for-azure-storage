# This Terraform Template deploys the Cloud Intelligence Dashboard for Azure

### Create IAM configuration used throughout project
resource "aws_iam_role" "GlueIAM" {
  name        = format("%s%s%s%s", var.PrefixCode, "iar", var.EnvironmentCode, "ccidazureglue")
  description = "Cloud Intelligence Dashboard for Azure IAM role for Glue"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "glue.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "iar", var.EnvironmentCode, "cidazureglue")
    rtype = "security"
  }
}

resource "aws_iam_role_policy" "GlueIAM" {
  name = format("%s%s%s%s", var.PrefixCode, "irp", var.EnvironmentCode, "cidazureglue")
  role = aws_iam_role.GlueIAM.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetPartition",
          "glue:UpdateDatabase",
          "glue:UpdateTable",
          "glue:UpdatePartition",
          "glue:BatchCreatePartition"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:glue:${var.Region}:${data.aws_caller_identity.current.account_id}:catalog",
          "${aws_glue_catalog_database.cidazure.arn}",
          "${aws_glue_catalog_table.cidazure.arn}",
        ]
      },
      {
        Action = [
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectTagging",
          "s3:PutObjectTagging"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.S3Bucket.arn}",
          "${aws_s3_bucket.S3Bucket.arn}/*"
        ]
      },
      {
        Action = [
          "kms:Encrypt",
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
          "logs:AssociateKmsKey",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:logs:${var.Region}:${data.aws_caller_identity.current.account_id}:log-group:*"
        ]
      },
      {
        Action = [
          "ssm:GetParameters",
          "ssm:GetParameter",
          "ssm:PutParameter"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:ssm:${var.Region}:${data.aws_caller_identity.current.account_id}:parameter/cidazure*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "cidazurequicksight" {
  name = format("%s%s%s%s", var.PrefixCode, "irp", var.EnvironmentCode, "cidazurequicksight")
  role = "aws-quicksight-service-role-v0"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucketMultipartUploads",
          "s3:GetBucketLocation",
          "s3:PutObject",
          "s3:GetObjectAcl",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
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
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_kms_key.KMSKey.arn}"
        ]
      }
    ]
  })
}
# TODO: Replace with QuickSight role-based access control to data sources that connect to Amazon S3 and Athena

#[Comment out for offline mode 1/1]
resource "aws_iam_role_policy" "disablemultipartpolicy" {
  name = format("%s%s%s%s", var.PrefixCode, "irp", var.EnvironmentCode, "disablemultipart")
  role = aws_iam_role.GlueIAM.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "lambda:GetFunctionConfiguration",
          "lambda:UpdateFunctionConfiguration"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_lambda_function.LambdaFunction01.arn}"
        ]
      }
    ]
  })
}

### Upload Glue Script
resource "aws_s3_object" "cidazuregluepy" {
  bucket = aws_s3_bucket.S3Bucket.id
  key    = "scripts/cid-azure-gluejob-tf.py"
  content = templatefile("cid-azure-gluejob-tf.py",
    {
      var_account_type     = var.AccountType
      var_bucket           = aws_s3_bucket.S3Bucket.id
      var_date_format      = var.AzureDateFormat
      var_error_folder     = "azureciderror"
      var_glue_database    = aws_glue_catalog_database.cidazure.name
      var_glue_table       = aws_glue_catalog_table.cidazure.name
      var_parquet_folder   = "azurecidparquet"
      var_parquet_path     = "s3://${aws_s3_bucket.S3Bucket.bucket}/azurecidparquet/"
      var_processed_folder = "azurecidprocessed"
      var_processed_path   = "s3://${aws_s3_bucket.S3Bucket.bucket}/azurecidprocessed/"
      var_raw_folder       = "azurecidraw"
      var_raw_path         = "s3://${aws_s3_bucket.S3Bucket.bucket}/azurecidraw/${var.AzureFolderPath}"
      var_lambda01_name    = format("%s%s%s%s", var.PrefixCode, "lmd", var.EnvironmentCode, "cidazurelambda01")
      SELECTED_TAGS        = var.AzureTags
    }
  )
}

### Create Glue Resources
resource "aws_glue_catalog_database" "cidazure" {
  name        = format("%s%s%s%s", var.PrefixCode, "gld", var.EnvironmentCode, "cidazure")
  description = "Glue catalog database used to process Azure Cloud Intelligence Dashboard data"
}

resource "aws_glue_catalog_table" "cidazure" {
  name          = format("%s%s%s%s", var.PrefixCode, "glt", var.EnvironmentCode, "cidazure")
  database_name = aws_glue_catalog_database.cidazure.name
  table_type    = "EXTERNAL_TABLE"
  description   = "Glue catalog table for raw data used to by Azure Cloud Intelligence Dashboard"

  parameters = {
    classification        = "parquet"
    EXTERNAL              = "TRUE"
    "parquet.compression" = "SNAPPY"
    typeOfData            = "file"
  }

  partition_keys {
    name = "month"
    type = "date"
  }

  storage_descriptor {
    location                  = "s3://${aws_s3_bucket.S3Bucket.bucket}/azurecidparquet"
    input_format              = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format             = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    compressed                = true
    stored_as_sub_directories = true

    ser_de_info {
      name                  = "my-stream"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"

      parameters = {
        "serialization.format" = 1
      }
    }
  }
}

resource "aws_glue_job" "cidazure" {
  name                   = format("%s%s%s%s", var.PrefixCode, "glj", var.EnvironmentCode, "cidazure")
  description            = "Glue ETL job for Azure Cloud Intelligence Dashboard"
  role_arn               = aws_iam_role.GlueIAM.arn
  glue_version           = "4.0"
  worker_type            = "G.1X"
  number_of_workers      = 5
  max_retries            = 0
  timeout                = 60
  security_configuration = aws_glue_security_configuration.cidazure.name
  command {
    script_location = "s3://${aws_s3_bucket.S3Bucket.bucket}/${aws_s3_object.cidazuregluepy.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--enable-glue-datacatalog" = "true"
    "--enable-spark-ui"         = "true"
    "--library-set"             = "analytics"
    "--enable-metrics"          = ""
    "--job-language"            = "python"
    "--enable-job-insights"     = "true"
    "--enable-auto-scaling"     = "true"
    "--job-bookmark-option"     = "job-bookmark-enable"
  }

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "glj", var.EnvironmentCode, "cidazure")
    rtype = "data"
  }
}

resource "aws_glue_security_configuration" "cidazure" {
  name = format("%s%s%s%s", var.PrefixCode, "glx", var.EnvironmentCode, "cidazure")

  encryption_configuration {
    cloudwatch_encryption {
      kms_key_arn                = aws_kms_key.KMSKey.arn
      cloudwatch_encryption_mode = "SSE-KMS"
    }

    job_bookmarks_encryption {
      kms_key_arn                   = aws_kms_key.KMSKey.arn
      job_bookmarks_encryption_mode = "CSE-KMS"
    }

    s3_encryption {
      kms_key_arn        = aws_kms_key.KMSKey.arn
      s3_encryption_mode = "SSE-KMS"
    }
  }
}

resource "aws_glue_trigger" "cidazure" {
  name        = format("%s%s%s%s", var.PrefixCode, "glt", var.EnvironmentCode, "cidazure")
  description = "Cloud Intelligence Dashboard for Azure Glue ETL job schedule"
  schedule    = var.GlueCopySchedule
  type        = "SCHEDULED"

  actions {
    job_name = aws_glue_job.cidazure.name
  }

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "glt", var.EnvironmentCode, "cidazure")
    rtype = "data"
  }
}

resource "aws_ssm_parameter" "DashboardDeploy" {
  name        = format("%s%s%s%s", var.PrefixCode, "smp", var.EnvironmentCode, "-cidazure-deploy_dashboard_command")
  type        = "String"
  value       = "cid-cmd deploy --resources https://raw.githubusercontent.com/aws-samples/aws-data-pipelines-for-azure-storage/main/CloudIntelligenceDashboardforAzure/CFN/cid-azure-dashboard.yaml --customer ${var.PrefixCode} --environment ${var.EnvironmentCode} --athena-database ${aws_glue_catalog_database.cidazure.name} --share-method account --athena-workgroup ${aws_athena_workgroup.cidazure.name} --quicksight-datasource-id AWSCIDforAzure --source-table ${aws_glue_catalog_table.cidazure.name} --dashboard-id ${var.PrefixCode}-${var.EnvironmentCode}-azure-cost"
  description = "Cloud Intelligence Dashboard for Azure parameter. Command used to deploy dashboard"

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "smp", var.EnvironmentCode, "-cidazure-deploy_dashboard_command")
    rtype = "data"
  }
}

resource "aws_ssm_parameter" "varbulkrun" {
  name        = "cidazure-var_bulk_run"
  type        = "String"
  value       = "true"
  description = "Cloud Intelligence Dashboard for Azure parameter. Set to true (lowercase t) if this is the first data copy or you are reprocessing, otherwise false."

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "smp", var.EnvironmentCode, "-cidazure-var_bulk_run")
    rtype = "data"
  }
  # Ensures the bulkrun parameter is not overwritten with subsequent applies
  lifecycle {
    ignore_changes = [ value ]
  }
}

### Create Athena resources
resource "aws_athena_workgroup" "cidazure" {
  name          = format("%s%s%s%s", var.PrefixCode, "atw", var.EnvironmentCode, "cidazure")
  description   = "Cloud Intelligence Dashboard for Azure Athena Workgroup"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.S3Bucket.bucket}/azurecidqueries"

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = aws_kms_key.KMSKey.arn
      }
    }
  }

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "atw", var.EnvironmentCode, "cidazure")
    rtype = "data"
  }
}

### Generate Athena saved query. named query is for reference only and not used as part of automation
resource "aws_athena_named_query" "cidazure" {
  name        = format("%s%s%s%s", var.PrefixCode, "atq", var.EnvironmentCode, "cidazure")
  description = "Cloud Intelligence Dashboard for Azure Athena Named Query"
  workgroup   = aws_athena_workgroup.cidazure.id
  database    = aws_glue_catalog_database.cidazure.name
  query       = "CREATE OR REPLACE VIEW ${aws_glue_catalog_table.cidazure.name}_athena_view AS SELECT * FROM ${aws_glue_catalog_table.cidazure.name} WHERE month >= DATE(to_iso8601(current_date - interval '6' month))"
}