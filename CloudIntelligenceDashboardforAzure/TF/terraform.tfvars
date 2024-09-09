# Parameters

# Common Settings
PrefixCode            = "cid"
EnvironmentCode       = "dv"
OwnerTag              = "Amazon Web Services"
EnvironmentTag        = "development"
QuickSightServiceRole = "aws-quicksight-service-role-v0"

# Microsoft Azure Settings
# START: Not Required when using Azure Example templates
AzureBlobURL       = "https://<mystorageaccount>.blob.core.windows.net/"
AzureApplicationID = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
AzureTenantID      = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
AzureSecretKey     = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
# END: Not Required when using Azure Example templates
AccountType        = "MCA"
AzureDateFormat    = "MM/dd/yyyy"
AzureFolderPath    = "directory/*"
AzureTags          = "Environment, CostCenter, System, Department"

AzureOverwritedataEnabled = "false"

# Export Settings
ExportType = "Standard"

# Data Copy Settings
AzureCopySchedule     = "cron(0 3 * * ? *)"
GlueCopySchedule      = "cron(0 4 * * ? *)"
BlobToS3SyncStartDate = "20220820"

# Advanced Settings
PartitionSize        = "104857600"
MaxPartitionsPerFile = "100"
UseFullFilePath      = "true"

# Regions and Availability Zones
Region = "eu-west-2"