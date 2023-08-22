import json
import math
import os
from datetime import datetime
from boto3 import client as Client
# noinspection PyUnresolvedReferences
from azure.identity import ClientSecretCredential
# noinspection PyUnresolvedReferences
from azure.storage.blob import BlobServiceClient

def try_strptime(s, fmts=['%d-%b-%y','%m/%d/%Y','%Y-%m-%d %H:%M:%S%z','%Y%m%d','%Y-%m-%d %H:%M:%S','%Y-%m-%d %H:%M:%S%Z']):
    for fmt in fmts:
        try:
            return datetime.strptime(s, fmt)
        except:
            continue

    return None

dt_format_code = '%Y-%m-%d %H:%M:%S'
dt_formats_to_try =['%d-%b-%y','%m/%d/%Y','%Y-%m-%d %H:%M:%S%z','%Y%m%d','%Y-%m-%d %H:%M:%S','%Y-%m-%d %H:%M:%S%Z']
class BlobInfo:

    def __init__(self, container, blob, useFullFilePath, lastmodified, size, partitionSize, valuePayload, contentSettings):
        self.container = container
        self.blob = blob
        self.fileName = os.path.basename(blob)
        self.lastmodified = lastmodified
        self.size = size
        self.partitionSize = partitionSize
        self.valuePayload = valuePayload
        self.contentType = contentSettings.content_type
        self.contentEncoding = contentSettings.content_encoding
        self.contentLanguage = contentSettings.content_language
        self.UseFullFilePath = useFullFilePath
        self.fullFilePath  = self.fileName
        if self.UseFullFilePath == 'true':
            self.fullFilePath = '' + self.blob
          # to retain container in file path use below
          # self.fullFilePath = '' + self.container + '/' + self.blob  
        

    def toJSON(self):
        return json.dumps(self, default=lambda o: o.__dict__,
                          sort_keys=True, indent=4)
        


def lambda_handler(event, context):
    # Retrieve the first SNS payload for populating variables
    response = event['Records'][0]['Sns'].get('Message', 'not found')
    values = json.loads(response)

    # Variables to obtain a secure token from Azure
    active_directory_tenant_id = values.get('tenantid', 'notFound')
    active_directory_application_id = values.get('appid', 'notFound')
    active_directory_application_secret = values.get('appsecret', 'notFound')
    oauth_url = values.get('oauth_url', 'notFound')

    # Only process blobs > begindate secret
    processStartDate = try_strptime(values.get('begindate', '1911-01-01 00:00:00'),dt_formats_to_try)
    latestdate = try_strptime(values.get('begindate', '1911-01-01 00:00:00'),dt_formats_to_try)

    # SNS ARN for the 2nd topic that triggers the Download lambda
    sns_arn_2 = values.get('sns_arn_l2', 'notFound')
    sns_arn_3 = values.get('sns_arn_l3', 'notFound')

    # Pull the ARN of the SecretManager Secret in case we do an update to the beginDate
    secret_arn = values.get('secret_arn', 'secretArnNotFound')

    partitionSize = int(values.get('partitionSize','5242880'))
    maxPartitionsPerFile = int(values.get('maxPartitions','9999'))
    UseFullFilePath = values.get('UseFullFilePath','True')

    # Retrieve a secure token with the Azure.Identity library
    token_credential = ClientSecretCredential(
        active_directory_tenant_id,
        active_directory_application_id,
        active_directory_application_secret
    )

    # Create a Blob Client with the Azure.Storage library
    blob_service_client = BlobServiceClient(
        account_url=oauth_url,
        credential=token_credential
    )
    client = Client('sns')

    # Gets all Azure Blob Storage containers available to the tenant/application
    all_containers = blob_service_client.list_containers(include_metadata=True)
    for container in all_containers:
        # Get all blobs in the container
        container_client = blob_service_client.get_container_client(container['name'])
        for blob in container_client.list_blobs():
            print(blob.last_modified.strftime(dt_format_code),type(blob.last_modified), processStartDate,type(processStartDate),latestdate,type(latestdate))
            fileTime = try_strptime(blob.last_modified.strftime(dt_format_code),dt_formats_to_try)
            size = blob.size
            partitionSize = partitionSize
            adaptiveCeiling = partitionSize * maxPartitionsPerFile
            if fileTime > latestdate:
                latestdate =fileTime

            # Send message to SNS for immediate processing
            if fileTime > processStartDate:
              
                # add to list
                if (size > partitionSize):
                    if(size > adaptiveCeiling):
                        # Adjusting the partitionSize for the MPlimits
                        partitionSize = int(math.ceil(size / adaptiveCeiling))
                    b = BlobInfo(container['name'], blob.name, UseFullFilePath, fileTime.strftime(dt_format_code), size, partitionSize, values, blob.content_settings)
                    print("Sent for Large File Processing - blob: ", blob.name)
                    response = client.publish(
                        TargetArn=sns_arn_3,
                        Message=json.dumps({'default': b.toJSON()}),
                        MessageStructure='json'
                    )
                    
                else:
                    b = BlobInfo(container['name'], blob.name, UseFullFilePath, fileTime.strftime(dt_format_code), size, partitionSize, values, blob.content_settings)
                    print("Sent for download - blob: ", blob.name)
                    response = client.publish(
                        TargetArn=sns_arn_2,
                        Message=json.dumps({'default': b.toJSON()}),
                        MessageStructure='json'
                    )
    # Adding blobname, lastmodified date to a list for sorting the latest file
    # Updating process date if it is actually bigger
    print("latest", latestdate,"processstart",processStartDate)
    if latestdate > processStartDate:
        client = Client('secretsmanager')
        response = client.get_secret_value(
            SecretId=secret_arn
        )
        print("latest", latestdate,"processstart",processStartDate)
        secret = response['SecretString']
        secret = secret.replace('"begindate":"' + values.get('begindate', '1911-01-01 00:00:00') + '"', '"begindate":"' + latestdate.strftime(dt_format_code) + '"')
        response['SecretString'] = secret
        client.update_secret(SecretId=secret_arn, SecretString=response['SecretString'])
    return 'success'
