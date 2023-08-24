"""
MIT No Attribution

Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
"""
import json
import os
import re
import time
from urllib import parse
from boto3 import client as Client
from azure.identity import ClientSecretCredential
from azure.storage.blob import BlobServiceClient
from datetime import datetime, timezone

def cloudwatch_printer(message: str, log_group='blob-to-s3-file-group', log_stream='blob-to-s3-file-stream'):
    """
    This function calls the CloudWatch API, creates a new log group and stream in case it doesn't exist and print into that stream a message.
    """
    cloudwatch_client = Client('logs')
    # Attemp to create log group and stream
    try:
        cloudwatch_client.create_log_group(logGroupName=log_group)
    except cloudwatch_client.exceptions.ResourceAlreadyExistsException:
        print(f'Failed to create group {log_group}: ResourceAlreadyExistsException')
    try:
        cloudwatch_client.create_log_stream(logGroupName=log_group, logStreamName=log_stream)
    except cloudwatch_client.exceptions.ResourceAlreadyExistsException:
        print(f'Failed to create stream {log_stream}: ResourceAlreadyExistsException')
    
    # Crating the log event
    cloudwatch_client.put_log_events(
        logGroupName=log_group,
        logStreamName=log_stream,
        logEvents=[
            {
                'timestamp': int(round(time.time() * 1000)),
                'message': message
            },
        ]
    )
    return 0

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
    
    # Preparing the message for the log event
    start_t = time.time()
    start_t_datetime = datetime.fromtimestamp(start_t, tz=timezone.utc)
    message = f"""
               INFO: started file upload to S3\n
               blobname: {blobName}\n
               destination bucket: {bucket_name}\n
               start time: {start_t_datetime}\n
               total file size: {blobSize}\n
               """
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
    # Preparing the message for the log event
    end_t = time.time()
    end_t_datetime = datetime.fromtimestamp(end_t, tz=timezone.utc)
    message = f"""
               INFO: File upload succesfuly uploaded\n
               blobname: {blobName}\n
               destination bucket: {bucket_name}\n
               start time: {start_t_datetime}\n
               end time: {end_t_datetime}\n
               total file size: {blobSize}\n
               duration: {end_t-start_t}\n
               """
    
    return {
        'statusCode': 200,
        'body': json.dumps(response)
    }
