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
import time
from boto3 import client as Client

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

# Function to combine downloaded parts
def lambda_handler(event, context):
    response = event['Records'][0]['Sns'].get('Message','not found')
    values = json.loads(response)

    s3 = Client("s3")

    bucket_name = values.get("bucket_name","")
    blobkey = values.get("blobkey","")
    mp_upload_id = values.get("UploadId","")
    finalPartNumber = values.get("PartNumber","")
    print("Final part to trigger the recombinator was: ::::: ", finalPartNumber)
    rp_parts_list = s3.list_parts(
        Bucket=bucket_name,
        Key=blobkey,
        UploadId=mp_upload_id
    )
    parts = []
    parts_raw = json.loads(json.dumps(rp_parts_list,default=str))
    for item in parts_raw['Parts']:
        parts.append({
            "ETag" : item.get('ETag',''),
            "PartNumber" : item.get("PartNumber")
        })

    mp_complete_response = s3.complete_multipart_upload(
            Bucket=bucket_name,
            Key=blobkey,
            MultipartUpload={
                'Parts': parts
            },
            UploadId=mp_upload_id
    
        )
    
    cloudwatch_printer(f'INFO: {blobkey} succesfully uploaded to S3')

    return {
        'statusCode': 200,
        'body': json.dumps(response)
    }
