# This Terraform Template deploys the Cloud Intelligence Dashboard for Azure

### Create IAM configuration used throughout project
resource "aws_iam_role" "GlueIAM" {
  name        = format("%s%s%s%s", var.PrefixCode, "iar", var.EnvironmentCode, "cidazureglue")
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
          "arn:aws:ssm:${var.Region}:${data.aws_caller_identity.current.account_id}:parameter/${var.PrefixCode}smp${var.EnvironmentCode}-cidazure-var_bulk_run"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "cidazurequicksight" {
  name = format("%s%s%s%s", var.PrefixCode, "irp", var.EnvironmentCode, "cidazurequicksight")
  role = var.QuickSightServiceRole
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

resource "aws_iam_role" "LogIAM" {
  name        = format("%s%s%s%s", var.PrefixCode, "iar", var.EnvironmentCode, "ccidazurelog")
  description = "Cloud Intelligence Dashboard for Azure IAM role for install logging"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "iar", var.EnvironmentCode, "cidazurelog")
    rtype = "security"
  }
}

resource "aws_iam_role_policy" "LogIAM" {
  name = format("%s%s%s%s", var.PrefixCode, "irp", var.EnvironmentCode, "cidazurelog")
  role   = aws_iam_role.LogIAM.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:CreateLogGroup"
        ]
        Resource = [
          "arn:aws:logs:${var.Region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.PrefixCode}lmd${var.EnvironmentCode}cidazurelambdalog",
          "arn:aws:logs:${var.Region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.PrefixCode}lmd${var.EnvironmentCode}cidazurelambdalog:*",
          "arn:aws:logs:${var.Region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.PrefixCode}lmd${var.EnvironmentCode}cidazurelambdalog:*:*"
        ]
      }
    ]
  })
}

### Upload Glue Scripts
resource "aws_s3_object" "cidazuregluepy" {
  bucket  = aws_s3_bucket.S3Bucket.id
  key     = "scripts/cid-azure-gluejob-tf.py"
  content = templatefile("../CFN/cid-azure-gluejob.py",{})
}

resource "aws_s3_object" "cidazuregluepyfocus" {
  bucket  = aws_s3_bucket.S3Bucket.id
  key     = "scripts/cid-azure-gluejob-tf-FOCUS-1.0.py"
  content = templatefile("../CFN/cid-azure-gluejob-FOCUS-1.0.py",{})
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
  count                  = var.ExportType == "Standard" ? 1 : 0
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
    "--var_raw_path"            = "s3://${aws_s3_bucket.S3Bucket.bucket}/azurecidraw/"
    "--var_parquet_path"        = "s3://${aws_s3_bucket.S3Bucket.bucket}/azurecidparquet/"
    "--var_processed_path"      = "s3://${aws_s3_bucket.S3Bucket.bucket}/azurecidprocessed/"
    "--var_glue_database"       = aws_glue_catalog_database.cidazure.name
    "--var_glue_table"          = aws_glue_catalog_table.cidazure.name
    "--var_bucket"              = aws_s3_bucket.S3Bucket.id
    "--var_raw_folder"          = "azurecidraw"
    "--var_processed_folder"    = "azurecidprocessed"
    "--var_parquet_folder"      = "azurecidparquet"
    "--var_date_format"         = var.AzureDateFormat
    "--var_folderpath"          = var.AzureFolderPath
    "--var_azuretags"           = var.AzureTags
    "--var_account_type"        = var.AccountType
    "--var_bulk_run_ssm_name"   = "${aws_ssm_parameter.varbulkrun.name}"
    "--var_error_folder"        = "azureciderror"
    "--var_lambda01_name"       = format("%s%s%s%s", var.PrefixCode, "lmd", var.EnvironmentCode, "cidazurelambda01")
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
  count       = var.ExportType == "Standard" ? 1 : 0
  name        = format("%s%s%s%s", var.PrefixCode, "glt", var.EnvironmentCode, "cidazure")
  description = "Cloud Intelligence Dashboard for Azure Glue ETL job schedule"
  schedule    = var.GlueCopySchedule
  type        = "SCHEDULED"

  actions {
    job_name = aws_glue_job.cidazure[count.index].name
  }

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "glt", var.EnvironmentCode, "cidazure")
    rtype = "data"
  }
}

resource "aws_glue_job" "cidazurefocus" {
  count                  = var.ExportType == "FOCUS" ? 1 : 0
  name                   = format("%s%s%s%s", var.PrefixCode, "glj", var.EnvironmentCode, "cidazurefocus")
  description            = "Glue ETL job for Azure Cloud Intelligence Dashboard"
  role_arn               = aws_iam_role.GlueIAM.arn
  glue_version           = "4.0"
  worker_type            = "G.1X"
  number_of_workers      = 5
  max_retries            = 0
  timeout                = 60
  security_configuration = aws_glue_security_configuration.cidazure.name
  command {
    script_location = "s3://${aws_s3_bucket.S3Bucket.bucket}/${aws_s3_object.cidazuregluepyfocus.key}"
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
    "--var_raw_path"            = "s3://${aws_s3_bucket.S3Bucket.bucket}/azurecidraw/"
    "--var_parquet_path"        = "s3://${aws_s3_bucket.S3Bucket.bucket}/azurecidparquetfocus/"
    "--var_processed_path"      = "s3://${aws_s3_bucket.S3Bucket.bucket}/azurecidprocessedfocus/"
    "--var_glue_database"       = aws_glue_catalog_database.cidazure.name
    "--var_glue_table"          = aws_glue_catalog_table.cidazure.name
    "--var_bucket"              = aws_s3_bucket.S3Bucket.id
    "--var_raw_folder"          = "azurecidraw"
    "--var_processed_folder"    = "azurecidprocessedfocus"
    "--var_parquet_folder"      = "azurecidparquetfocus"
    "--var_date_format"         = var.AzureDateFormat
    "--var_folderpath"          = var.AzureFolderPath
    "--var_account_type"        = var.AccountType
    "--var_bulk_run_ssm_name"   = "${aws_ssm_parameter.varbulkrun.name}"
    "--var_error_folder"        = "azureciderrorfocus"
    "--var_lambda01_name"       = format("%s%s%s%s", var.PrefixCode, "lmd", var.EnvironmentCode, "cidazurelambda01")
  }

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "glj", var.EnvironmentCode, "cidazurefocus")
    rtype = "data"
  }
}

resource "aws_glue_trigger" "cidazurefocus" {
  count       = var.ExportType == "FOCUS" ? 1 : 0
  name        = format("%s%s%s%s", var.PrefixCode, "glt", var.EnvironmentCode, "cidazure")
  description = "Cloud Intelligence Dashboard for Azure Glue ETL job schedule"
  schedule    = var.GlueCopySchedule
  type        = "SCHEDULED"

  actions {
    job_name = aws_glue_job.cidazurefocus[count.index].name
  }

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "glt", var.EnvironmentCode, "cidazure")
    rtype = "data"
  }
}

resource "aws_ssm_parameter" "dashboarddeploy" {
  name        = format("%s%s%s%s", var.PrefixCode, "smp", var.EnvironmentCode, "-cidazure-deploy_dashboard_command")
  type        = "String"
  value       = "cid-cmd deploy --resources https://raw.githubusercontent.com/aws-samples/aws-data-pipelines-for-azure-storage/main/CloudIntelligenceDashboardforAzure/CFN/cid-azure-dashboard.yaml --customer ${var.PrefixCode} --environment ${var.EnvironmentCode} --athena-database ${aws_glue_catalog_database.cidazure.name} --share-method account --athena-workgroup ${aws_athena_workgroup.cidazure.name} --quicksight-datasource-id AWSCIDforAzure --source-table ${aws_glue_catalog_table.cidazure.name} --dashboard-id ${var.PrefixCode}-${var.EnvironmentCode}-azure-cost --quicksight-datasource-role ${var.QuickSightServiceRole}"
  description = "Cloud Intelligence Dashboard for Azure parameter. Command used to deploy dashboard"

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "smp", var.EnvironmentCode, "-cidazure-deploy_dashboard_command")
    rtype = "parameter"
  }
}

resource "aws_ssm_parameter" "varbulkrun" {
  name        = format("%s%s%s%s", var.PrefixCode, "smp", var.EnvironmentCode, "-cidazure-var_bulk_run")
  type        = "String"
  value       = var.AzureOverwritedataEnabled == "true" ? "false" : "true"
  description = "Cloud Intelligence Dashboard for Azure parameter. Set to true (lowercase t) if this is the first data copy or you are reprocessing, otherwise false."

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "smp", var.EnvironmentCode, "-cidazure-var_bulk_run")
    rtype = "parameter"
  }
  # Ensures the bulkrun parameter is not overwritten with subsequent applies
  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "gluenotebookargs" {
  name        = format("%s%s%s%s", var.PrefixCode, "smp", var.EnvironmentCode, "-cidazure-gluenotebookargs")
  type        = "String"
  value       = <<EOF
var_raw_path = "s3://${aws_s3_bucket.S3Bucket.bucket}/azurecidraw/"
var_parquet_path = "s3://${aws_s3_bucket.S3Bucket.bucket}/azurecidparquet/"
var_processed_path = "s3://${aws_s3_bucket.S3Bucket.bucket}/azurecidprocessed/"
var_glue_database = "${aws_glue_catalog_database.cidazure.name}"
var_glue_table = "${aws_glue_catalog_table.cidazure.name}"
var_bucket = "${aws_s3_bucket.S3Bucket.id}"
var_raw_folder = "azurecidraw"
var_processed_folder = "azurecidprocessed"
var_parquet_folder = "azurecidparquet"
var_date_format = "${var.AzureDateFormat}"
var_folderpath = "${var.AzureFolderPath}"
var_azuretags = "${var.AzureTags}"
var_account_type = "${var.AccountType}"
var_bulk_run_ssm_name = "${aws_ssm_parameter.varbulkrun.name}"
var_error_folder = "azureciderror"
var_lambda01_name = "${aws_lambda_function.LambdaFunction01.function_name}"
var_raw_fullpath = var_raw_path + var_folderpath
SELECTED_TAGS = var_azuretags.split(", ")
EOF
  description = "Cloud Intelligence Dashboard for Azure parameters. Used to setup Glue Notebook parameters for interactive sessions."

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "smp", var.EnvironmentCode, "-cidazure-gluenotebookargs")
    rtype = "parameter"
  }
}

resource "aws_ssm_parameter" "gluenotebookargsfocus" {
  name        = format("%s%s%s%s", var.PrefixCode, "smp", var.EnvironmentCode, "-cidazure-gluenotebookargsfocus")
  type        = "String"
  value       = <<EOF
var_raw_path = "s3://${aws_s3_bucket.S3Bucket.bucket}/azurecidraw/"
var_parquet_path = "s3://${aws_s3_bucket.S3Bucket.bucket}/azurecidparquetfocus/"
var_processed_path = "s3://${aws_s3_bucket.S3Bucket.bucket}/azurecidprocessedfocus/"
var_glue_database = "${aws_glue_catalog_database.cidazure.name}"
var_glue_table = "${aws_glue_catalog_table.cidazure.name}"
var_bucket = "${aws_s3_bucket.S3Bucket.id}"
var_raw_folder = "azurecidraw"
var_processed_folder = "azurecidprocessedfocus"
var_parquet_folder = "azurecidparquetfocus"
var_date_format = "${var.AzureDateFormat}"
var_folderpath = "${var.AzureFolderPath}"
var_account_type = "${var.AccountType}"
var_bulk_run_ssm_name = "${aws_ssm_parameter.varbulkrun.name}"
var_error_folder = "azureciderrorfocus"
var_lambda01_name = "${aws_lambda_function.LambdaFunction01.function_name }"
var_raw_fullpath = var_raw_path + var_folderpath
EOF
  description = "Cloud Intelligence Dashboard for Azure parameters. Used to setup Glue Notebook parameters with FOCUS specification for interactive sessions."

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "smp", var.EnvironmentCode, "-cidazure-gluenotebookargsfocus")
    rtype = "parameter"
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
  description = "Cloud Intelligence Dashboard for Azure standard export Athena Named Query"
  workgroup   = aws_athena_workgroup.cidazure.id
  database    = aws_glue_catalog_database.cidazure.name
  query       = "CREATE OR REPLACE VIEW ${aws_glue_catalog_table.cidazure.name}_athena_view AS SELECT * FROM ${aws_glue_catalog_table.cidazure.name} WHERE month >= DATE(to_iso8601(current_date - interval '6' month))"
}

resource "aws_athena_named_query" "cidazurefocussummary" {
  name        = format("%s%s%s%s", var.PrefixCode, "atq", var.EnvironmentCode, "cidazure-focus-summary-view")
  description = "Cloud Intelligence Dashboard for Azure FOCUS export Athena Named Query Summary View"
  workgroup   = aws_athena_workgroup.cidazure.id
  database    = aws_glue_catalog_database.cidazure.name
  query = templatefile("cid-azure-focus_summary_view.sql",
    {
      var_glue_database = aws_glue_catalog_database.cidazure.name
      var_glue_table    = aws_glue_catalog_table.cidazure.name
    }
  )
}

resource "aws_athena_named_query" "cidazurefocusresource" {
  name        = format("%s%s%s%s", var.PrefixCode, "atq", var.EnvironmentCode, "cidazure-focus-resource-view")
  description = "Cloud Intelligence Dashboard for Azure FOCUS export Athena Named Query Resource View"
  workgroup   = aws_athena_workgroup.cidazure.id
  database    = aws_glue_catalog_database.cidazure.name
  query = templatefile("cid-azure-focus_resource_view.sql",
    {
      var_glue_database = aws_glue_catalog_database.cidazure.name
      var_glue_table    = aws_glue_catalog_table.cidazure.name
    }
  )
}
### Create installation log
resource "aws_lambda_function" "LambdaFunctionLog" {
  filename      = "cid-azure-lambdalog.zip"
  function_name = format("%s%s%s%s", var.PrefixCode, "lmd", var.EnvironmentCode, "cidazurelambdalog")
  description   = "Cloud Intelligence Dashboard for Azure Lambda function to record install of FOCUS solution"
  handler       = "cid-azure-lambdalog.lambda_handler"
  kms_key_arn   = aws_kms_key.KMSKey.arn
  role          = aws_iam_role.LogIAM.arn
  runtime       = "python3.12"
  memory_size   = 128
  timeout       = 15

  environment {
    variables = {
      API_ENDPOINT = "https://okakvoavfg.execute-api.eu-west-1.amazonaws.com/"
      account_id = data.aws_caller_identity.current.account_id
      dashboard_id = format("%s%s", "cid-azure-", var.ExportType)
    }
  }
  ephemeral_storage {
    size = 512
  }
  tracing_config {
    mode = "Active"
  }

  tags = {
    Name  = format("%s%s%s%s", var.PrefixCode, "lmd", var.EnvironmentCode, "cidazurelambdalog")
    rtype = "compute"
  }
}

resource "aws_lambda_invocation" "LambdaFunctionLog" {
  function_name = aws_lambda_function.LambdaFunctionLog.function_name

  input = jsonencode({
    dashboard_id = format("%s%s", "cid-azure-", var.ExportType)
    account_id   = data.aws_caller_identity.current.account_id
  })

  lifecycle_scope = "CREATE_ONLY"
}