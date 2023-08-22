import json
from boto3 import client as Client
from boto3 import resource as Resource
from azure.identity import ClientSecretCredential
from azure.storage.blob import BlobServiceClient

# Function to upload large file part to S3
def lambda_handler(event, context):
    response = event['Records'][0]['Sns'].get('Message','not found')
    values = json.loads(response)
    retries_active = values.get("retries_active","true")
    current_retry_count = values.get("current_retry_count","notFound")
    
    # Check if retries is active and retry count is less than 4
    print(current_retry_count)
    if(current_retry_count < 4):    # Else publish to sns topic to retain multipart download and preserve the json
        print('Accessed Download Section')
        oauth_url = values.get('oauth_url','urlNotFound')
        bucket_name = values.get('bucket_name','bucketNotFound')
        blobName = values.get("blobName","notFound")
        currentOffset = values.get("currentOffset","notFound")
        bytesToDownload = values.get("bytesToDownload","notFound")
        blobkey = values.get("blobkey","notFound")
        containerName = values.get("containerName","notFound")
        mp_upload_id = values.get("mp_upload_id","notFound")
        part_number = values.get("part_number","notFound")
        total_parts = values.get("total_parts",0)
        active_directory_tenant_id = values.get("active_directory_tenant_id","notFound")
        active_directory_application_id = values.get("active_directory_application_id","notFound")
        active_directory_application_secret = values.get("active_directory_application_secret","notFound")
        sns_home = values.get("sns_home","notFound")
        sns_destination = values.get("sns_destination","notFound")
        client = Client('sns')

        token_credential = ClientSecretCredential(
            active_directory_tenant_id,
            active_directory_application_id,
            active_directory_application_secret
        )
        blob_service_client = BlobServiceClient(
            account_url=oauth_url,
            credential=token_credential
        )
        print('credentials auth')
        blob_client = blob_service_client.get_blob_client(container=containerName, blob=blobName)
        print('begin download')
        s3r = Resource('s3')
        download_stream = blob_client.download_blob(
            offset=currentOffset,
            length=bytesToDownload
        )
        print(blobkey)
        multipart_upload_part = s3r.MultipartUploadPart(
            bucket_name,
            blobkey,
            mp_upload_id,
            part_number)
        print(multipart_upload_part)
        mp_part_upload_response = multipart_upload_part.upload(
            Body=download_stream.readall()
        )
        print(mp_part_upload_response)

        # Check the parts manifest and see if it should trigger recombinator function
        s3 = Client('s3')
        rp_parts_list = s3.list_parts(
            Bucket=bucket_name,
            Key=blobkey,
            UploadId=mp_upload_id
        )
 
        # Check to see if the total parts are there and proceed or exit
        parts = json.loads(json.dumps(rp_parts_list,default=str))
        try:
            my_part = ([key for key in parts['Parts'] if key['PartNumber'] == int(part_number) ]).pop()
            if(len(parts['Parts']) == total_parts):
                part_output = {
                    "bucket_name": bucket_name ,
                    "blobkey": blobkey ,
                    "UploadId": mp_upload_id ,
                    "ETag" : my_part.get("ETag","") ,
                    "PartNumber" : my_part.get("PartNumber","")
                }
                response = client.publish(
                    TargetArn=sns_destination,
                    Message=json.dumps({'default': json.dumps(part_output)}),
                    MessageStructure='json'
                )
            
        except:
            print("Something went wrong - phoning home for retry")
            print("Failure Downloading - blob: ", blobName,' part: ', part_number, 'mp_upload_id: ', mp_upload_id)
            inputParams = {
                        'oauth_url': oauth_url,
                        'currentOffset': currentOffset,
                        'bytesToDownload':bytesToDownload,
                        'bucket_name':bucket_name,
                        'blobkey':blobkey,
                        'blobName':blobName,
                        'containerName':containerName,
                        'mp_upload_id':mp_upload_id,
                        'part_number':part_number,
                        'active_directory_tenant_id':active_directory_tenant_id,
                        'active_directory_application_id':active_directory_application_id,
                        'active_directory_application_secret':active_directory_application_secret,
                        'retries_active': retries_active,
                        'current_retry_count': current_retry_count+1,
                        'sns_home': sns_home,
                        'sns_destination': sns_destination
                    }
            response = client.publish(
                TargetArn=sns_home,
                Message=json.dumps({'default': json.dumps(inputParams)}),
                MessageStructure='json'
            )
    return {
        'statusCode': 200,
        'body': json.dumps(response)
    }
