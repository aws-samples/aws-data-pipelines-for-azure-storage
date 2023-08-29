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
import math
import re
import time
from urllib import parse
from boto3 import client as Client
from datetime import datetime, timezone

## For future log consolidation
# def cloudwatch_printer(message: str, log_group='blob-to-s3-file-group', log_stream='blob-to-s3-file-stream'):
#     """
#     This function calls the CloudWatch API, creates a new log group and stream in case it doesn't exist and print into that stream a message.
#     """
#     cloudwatch_client = Client('logs')
#     # Attemp to create log group and stream
#     try:
#         cloudwatch_client.create_log_group(logGroupName=log_group)
#     except cloudwatch_client.exceptions.ResourceAlreadyExistsException:
#         print(f'Failed to create group {log_group}: ResourceAlreadyExistsException')
#     try:
#         cloudwatch_client.create_log_stream(logGroupName=log_group, logStreamName=log_stream)
#     except cloudwatch_client.exceptions.ResourceAlreadyExistsException:
#         print(f'Failed to create stream {log_stream}: ResourceAlreadyExistsException')
    
#     # Crating the log event
#     cloudwatch_client.put_log_events(
#         logGroupName=log_group,
#         logStreamName=log_stream,
#         logEvents=[
#             {
#                 'timestamp': int(round(time.time() * 1000)),
#                 'message': message
#             },
#         ]
#     )
#     return 0

# Function to initiate a multipart file upload to S3
def lambda_handler(event, context):
    start_t = time.time()

    response = event['Records'][0]['Sns'].get('Message','not found')
    values = json.loads(response)
    # BlobInfo contains the values payload as a property so loading that separately as valuePayload
    valuePayload = json.loads(json.dumps(values['valuePayload']))
    sns_arn_4 = valuePayload.get('sns_arn_l4', 'notFound')
    sns_arn_5 = valuePayload.get('sns_arn_l5', 'notFound')
    active_directory_tenant_id = valuePayload.get('tenantid','notFound')
    active_directory_application_id = valuePayload.get('appid','notFound')
    active_directory_application_secret = valuePayload.get('appsecret','notFound')
    oauth_url = valuePayload.get('oauth_url','urlNotFound')
    retries_active = valuePayload.get('retiesActive','false')
    bucket_name = valuePayload.get('bucket_name','bucketNotFound')
    containerName = values.get("container","notFound")
    blobName = values.get("blob","notFound")
    fileName = values.get("fileName","notFound")
    # TODO: if blobSize > someArbituary value: increase lambda specs or perform partition download
    blobSize = values.get("size","notFound")
    partitionSize = values.get('partitionSize',104857600)
    blobLastModified = values.get("lastmodified","1900-01-01 00:00:00")
    s3 = Client('s3')
    tags = {"container": containerName,"blobname": re.sub("[^\w.:+=@_/-]", "-",blobName),"size": blobSize, "lastmodified": blobLastModified}
    blobkey = values.get('fullFilePath',''+'/'+fileName)

    print("INFO: File started being uploaded") #  TODO: specify the log group and stream, if not a predefined ones will be utilized
    mp_upload_id = s3.create_multipart_upload(
        Bucket=bucket_name,
        Key=blobkey,
        Tagging=parse.urlencode(tags)
        ).get('UploadId','')
    print("mpuploadid",mp_upload_id)
    blob_partitions = int(math.ceil(blobSize / partitionSize))
    end_t = time.time()

    # Preparing the message for the log event
    start_t_datetime = datetime.fromtimestamp(start_t, tz=timezone.utc)
    end_t_datetime = datetime.fromtimestamp(end_t, tz=timezone.utc)
    message = f"""
               INFO: File succesfully uploaded to S3\n
               blobname: {blobName}\n
               destination bucket: {bucket_name}\n
               start time: {start_t_datetime}\n
               end time: {end_t_datetime}\n
               files copied: {blob_partitions}\n
               total file size: {blobSize}\n
               duration: {end_t-start_t}\n
               """
    print(message) #  TODO: specify the log group and stream, if not a predefined ones will be utilized

    client = Client('sns')

    for i in range(blob_partitions):
        currentOffset = i * partitionSize
        bytesToDownload = partitionSize - i
        if(bytesToDownload > 0):
            inputParams = {
                'oauth_url': oauth_url,
                'currentOffset': currentOffset,
                'bytesToDownload':bytesToDownload,
                'bucket_name':bucket_name,
                'blobkey':blobkey,
                'blobName':blobName,
                'containerName':containerName,
                'mp_upload_id':mp_upload_id,
                'part_number':i+1,
                'total_parts': blob_partitions ,
                'active_directory_tenant_id':active_directory_tenant_id,
                'active_directory_application_id':active_directory_application_id,
                'active_directory_application_secret':active_directory_application_secret,
                'retries_active': retries_active,
                'current_retry_count': 0,
                'sns_home': sns_arn_4,
                'sns_destination': sns_arn_5
             }
            print("Processing - blob: ", blobName,' part: ', i, 'mp_upload_id: ', mp_upload_id,'blobkey: ',blobkey)
            response = client.publish(
                TargetArn=sns_arn_4,
                Message=json.dumps({'default': json.dumps(inputParams)}),
                MessageStructure='json'
            )
    return {
        'statusCode': 200,
        'body': json.dumps(response)
    }
