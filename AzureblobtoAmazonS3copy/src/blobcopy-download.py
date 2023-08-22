import json
import os
import re
from urllib import parse
from boto3 import client as Client
from azure.identity import ClientSecretCredential
from azure.storage.blob import BlobServiceClient

# Azure Blob Copy function to retrieve the blob file via info from the SNS topic
# New secure token created for the Azure connection to avoid connection noise and enable distinct blob downloads
def lambda_handler(event, context):

    response = event['Records'][0]['Sns'].get('Message','not found')
    # The initial json loaded into values is the BlobInfo object
    # BlobInfo contains the values payload as a property, loading that separately as valuePayload
    values = json.loads(response)
    
    valuePayload = json.loads(json.dumps(values['valuePayload']))
    # accountName = valuePayload.get('account_name','nameNotFound')
    active_directory_tenant_id = valuePayload.get('tenantid','notFound')
    active_directory_application_id = valuePayload.get('appid','notFound') 
    active_directory_application_secret = valuePayload.get('appsecret','notFound')
    oauth_url = valuePayload.get('oauth_url','urlNotFound')
    
    bucket_name = valuePayload.get('bucket_name','bucketNotFound')
    containerName = values.get("container","notFound")
    blobName = values.get("blob","notFound")
    fileName = values.get("fileName","notFound")
    # TODO: if blobSize > someArbituary value: increase lambda specs or perform partition download
    blobSize = values.get("size","notFound")
    blobLastModified = values.get("lastmodified","1900-01-01 00:00:00")
    blobKey = values.get('fullFilePath',''+'/'+fileName)
    token_credential = ClientSecretCredential(
        active_directory_tenant_id,
        active_directory_application_id,
        active_directory_application_secret
    )
    blob_service_client = BlobServiceClient(
        account_url=oauth_url, 
        credential=token_credential
    )

    # Blob_client to directly retrieves the blob from the specified container
    blob_client = blob_service_client.get_blob_client(container=containerName, blob=blobName)
    os.chdir('/tmp')

    # Upload the file to the user specified S3 bucket
    with open(fileName, "wb") as my_blob:
        download_stream = blob_client.download_blob()
        my_blob.write(download_stream.readall())
        s3 = Client('s3')
        tags = {"container": containerName,"blobname": re.sub("[^\w.:+=@_/-]", "-",blobName),"size": blobSize, "lastmodified": blobLastModified}

        s3.upload_file(
            Filename = fileName,
            Bucket =  bucket_name,
            Key = blobKey,
            ExtraArgs = {"Tagging": parse.urlencode(tags)}
            )
       
    
    return {
        'statusCode': 200,
        'body': json.dumps(response)
    }
