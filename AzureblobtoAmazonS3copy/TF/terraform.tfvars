# Parameters

# Common Settings
PrefixCode      = "etl"
EnvironmentCode = "dv"
OwnerTag        = "Amazon Web Services"
EnvironmentTag  = "Development"

# Microsoft Azure Settings
# NOTE: Not Required when using Azure Example templates
AzureBlobURL       = "https://<mystorageaccount>.blob.core.windows.net/"
AzureApplicationID = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
AzureTenantID      = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
AzureSecretKey     = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Data Copy Settings
AzureCopySchedule     = "cron(0 3 * * ? *)"
BlobToS3SyncStartDate = "20220820"

# Advanced Settings
PartitionSize        = "104857600"
MaxPartitionsPerFile = "100"
UseFullFilePath      = "true"

# Regions and Availability Zones
Region = "eu-west-2"