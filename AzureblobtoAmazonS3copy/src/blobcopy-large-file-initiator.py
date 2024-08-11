import json
import math
from urllib import parse
from boto3 import client as Client
import re

# Function to initiate a multipart file upload to S3
def lambda_handler(event, context):
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
    
    mp_upload_id = s3.create_multipart_upload(
        Bucket=bucket_name,
        Key=blobkey,
        Tagging=parse.urlencode(tags)
        ).get('UploadId','')
    print("mpuploadid",mp_upload_id)
    blob_partitions = int(math.ceil(blobSize / partitionSize))

    client = Client('sns')

    for i in range(blob_partitions):
        currentOffset = i * partitionSize
        bytesToDownload = min(partitionSize, blobSize - currentOffset)
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
