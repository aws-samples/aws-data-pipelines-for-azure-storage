# Parameters

# Common Settings
PrefixCode            = "cid"
EnvironmentCode       = "tf"
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
AzureFolderPath    = "directory/*/*"

AzureOverwritedataEnabled = "true"

# Export Settings
ExportType = "Standard"
AzureFocusVersion = "v1.0r2"

# Data Copy Settings
AzureCopySchedule     = "cron(0 3 * * ? *)"
GlueCopySchedule      = "cron(0 4 * * ? *)"
BlobToS3SyncStartDate = "20220820"

# Advanced Settings
PartitionSize        = "104857600"
MaxPartitionsPerFile = "100"
UseFullFilePath      = "true"
AzureTags            = "Environment, CostCenter, System, Department"

# Regions and Availability Zones
Region = "eu-west-2"