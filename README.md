Welcome! This repository contains two projects.

- [Azure blob to Amazon S3 Copy](#azure-blob-to-amazon-s3-copy)
- [Cloud intelligence Dashboard for Azure](#cloud-intelligence-dashboard-for-azure)
- [Contributing](#contributing)
- [License](#license)

---

## Azure blob to Amazon S3 Copy

Copy data from Azure blob storage to Amazon S3

![Azure blob to Amazon S3 architecture](https://static.us-east-1.prod.workshops.aws/public/f68ceac7-ccda-4cf5-b04a-9873857b025a/static/images/azs3copy-midlevel-grey.png)

For AWS **CloudFormation** installation, follow instructions in the [How to copy data from Azure Blob Storage to Amazon S3 using code](https://aws-blogs-prod.amazon.com/modernizing-with-aws/azure-blob-to-amazon-s3/) blog post.

For **Terraform** installation follow the instructions below.

1. Download / Clone repository

2. Locally, maintain the folder structure as is, and execute Terraform builds from the TF directory. Both the TF and CFN folders are necessary.

3. You can use the [example](https://github.com/aws-samples/aws-data-pipelines-for-azure-storage/tree/main/AzureblobtoAmazonS3copy/TF/AzureExample) in the *AzureblobtoAmazonS3copy* folder to configure an Azure Storage account. Just move the files to the AzureblobtoAmazonS3copy/TF directory. If you decide to use this method, please edit the specified lines in *azs3copy-aws.tf* as below:

```
## NOTE: Comment out these lines if deploying Azure Example
#resource "aws_secretsmanager_secret_version" "SecretsManagerSecret" {
#  secret_id = aws_secretsmanager_secret.SecretsManagerSecret.id
#  secret_string = jsonencode({
#    bloburl     = var.AzureBlobURL 
#    tenantid    = var.AzureTenantID
#    appid       = var.AzureApplicationID
#    appsecret   = var.AzureSecretKey
#    bucket_name = "${aws_s3_bucket.S3Bucket.bucket}"
#    isactive    = "True"
#    begindate   = var.BlobToS3SyncStartDate
#    sns_arn_l1  = "${aws_sns_topic.SNSTopicL1L2.arn}"
#    sns_arn_l2  = "${aws_sns_topic.SNSTopicL2L3.arn}"
#    sns_arn_l3  = "${aws_sns_topic.SNSTopicLargeFileInit.arn}"
#    sns_arn_l4  = "${aws_sns_topic.SNSTopicLargeFilePart.arn}"
#    sns_arn_l5  = "${aws_sns_topic.SNSTopicLargeFileRecomb.arn}"
#  })
#}

# NOTE: Uncomment these lines if deploying Azure Example
 resource "aws_secretsmanager_secret_version" "SecretsManagerSecret" {
   secret_id = aws_secretsmanager_secret.SecretsManagerSecret.id
   secret_string = jsonencode({
     bloburl     = azurerm_storage_account.StorageAccount.primary_blob_endpoint
     tenantid    = data.azurerm_client_config.current.tenant_id
     appid       = azuread_application.AppRegistration.application_id
     appsecret   = azuread_application_password.AppPassword.value
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
```

2. Configure `terraform.tfvars`. Refer to descriptions in `variables-aws.tf` for help.

3. Run `terraform apply` from the *AzureblobtoAmazonS3copy/TF* directory. 

---

## Cloud intelligence Dashboard for Azure

View Microsoft Azure usage data in Amazon QuickSight.

![Cloud Intelligence Dashboard for Azure architecture](https://static.us-east-1.prod.workshops.aws/public/f68ceac7-ccda-4cf5-b04a-9873857b025a/static/images/cidazure-midlevel-grey.png)

For Cloudformation or Terraform installation, follow instructions in the [Cloud Intelligence Dashboard for Azure](https://catalog.workshops.aws/cidforazure) workshop.

To understand how the Azure Cost Usage files should be provided, take a look at the [sample CSV file](https://github.com/aws-samples/aws-data-pipelines-for-azure-storage/blob/main/CloudIntelligenceDashboardforAzure/cid-azure-sample.csv).

---

## Contributing

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

---

## License

This library is licensed under the MIT-0 License. See the [LICENSE](https://github.com/aws-samples/aws-data-pipelines-for-azure-storage/blob/main/LICENSE) file.

---
