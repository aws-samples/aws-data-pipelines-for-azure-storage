# AWS variables for the Cloud Intelligence Dashboard for Azure

# Common Settings
variable "PrefixCode" {
  description = "Prefix used to name all resources created by this CloudFormation template. Cannot be 'aws'. e.g. department name, business unit, project name"
  type        = string
  default     = "etl"
}
variable "EnvironmentCode" {
  description = "Code used to name all resources created by this CloudFormation template e.g. 'pd' for production"
  type        = string
  default     = "dv"
}
variable "OwnerTag" {
  description = "Owner tag value. All resources are created with an 'Owner' tag and the value you set here. e.g. finops, devops, IT shared services, etc."
  type        = string
  default     = "Amazon Web Services"
}
variable "EnvironmentTag" {
  description = "Environment tag value. All resources are created with an 'Environment' tag and the value you set here. e.g. production, staging, development"
  type        = string
  default     = "Production"
}

# Microsoft Azure Settings
variable "AccountType" {
  description = "Microsoft Azure account type. MCA or EA"
  type        = string
  default     = "MCA"

  validation {
    condition     = var.AccountType == "MCA" || var.AccountType == "EA"
    error_message = "valid values: MCA, EA"
  }
}
variable "AzureBlobURL" {
  description = "Microsoft Azure Primary Blob endpoint URL"
  type        = string
  default     = "https://<mystorageaccount>.blob.core.windows.net/"
}
variable "AzureApplicationID" {
  description = "Microsoft Azure Application ID"
  type        = string
  default     = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
variable "AzureTenantID" {
  description = "Microsoft Azure Tenant ID"
  type        = string
  default     = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
variable "AzureSecretKey" {
  description = "Microsoft Azure Client Secret"
  type        = string
  default     = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
}
variable "AzureDateFormat" {
  description = "Format of date in Azure cost export, check the date column of your Azure csv export to verify."
  type        = string
  default     = "MM/dd/yyyy"

  validation {
    condition     = var.AzureDateFormat == "MM/dd/yyyy" || var.AzureDateFormat == "dd/MM/yyyy" || var.AzureDateFormat == "yyyy-MM-dd"
    error_message = "valid values: MM/dd/yyyy, dd/MM/yyyy, yyyy-MM-dd"
  }
}
variable "AzureFolderPath" {
  description = "Path to Azure cost export folders, used by AWS Glue job. The default value is setup for <azure storage account>/<azure storage container>/directory/*"
  type        = string
  default     = "directory/*"
}
variable "AzureTags" {
  description = "List of Azure tags names you would like to bring across to QuickSight. WARNING leave a space after each comma. Each tag name must be encapsulated in single quotes. You will need at least one value, make one up if you don't have anything. Case sensitive."
  type        = string
  default     = "'Environment', 'CostCenter', 'System,', 'Department'"
}

# Data Copy Settings
variable "AzureCopySchedule" {
  description = "Scheduled time (UTC) for Azure data pull. Must be a CRON expression. The default sets the schedule to 3am daily"
  type        = string
  default     = "cron(0 3 * * ? *)"
}
variable "GlueCopySchedule" {
  description = "Scheduled time (UTC) for Glue data processing. Must be a CRON expression. The default sets the schedule to 4am daily. Must be after Azure data pull above"
  type        = string
  default     = "cron(0 4 * * ? *)"
}
variable "BlobToS3SyncStartDate" {
  description = "Minimum age of the objects to be copied. Must be a valid format (YYYYMMDD)"
  type        = string
  default     = "20220820"
}

# Advanced Settings
variable "PartitionSize" {
  description = "Multipart upload partition size in bytes"
  type        = string
  default     = "104857600"
}
variable "MaxPartitionsPerFile" {
  description = "The maximum amount of partitions to create for each multi part file. Must be an integer between 5 and 10000"
  type        = string
  default     = "100"
}
variable "UseFullFilePath" {
  description = "Retain Azure storage path"
  type        = bool
  default     = "true"
}

# Regions and Availability Zones
variable "Region" {
  description = "AWS deployment region"
  type        = string
}