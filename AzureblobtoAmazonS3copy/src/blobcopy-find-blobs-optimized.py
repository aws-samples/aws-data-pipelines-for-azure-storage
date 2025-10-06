import json
import math
import os
from datetime import datetime
from boto3 import client as Client
from azure.identity import ClientSecretCredential
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
        self.fullFilePath = self.fileName
        if self.UseFullFilePath == 'true':
            self.fullFilePath = '' + self.blob

    def toJSON(self):
        return json.dumps(self, default=lambda o: o.__dict__, sort_keys=True, indent=4)

def lambda_handler(event, context):
    response = event['Records'][0]['Sns'].get('Message', 'not found')
    values = json.loads(response)

    # Get pagination parameters
    batch_size = int(values.get('batch_size', '1000'))  # Process 1000 blobs per execution
    container_name = values.get('container_name', None)  # Process specific container
    continuation_token = values.get('continuation_token', None)
    
    active_directory_tenant_id = values.get('tenantid', 'notFound')
    active_directory_application_id = values.get('appid', 'notFound')
    active_directory_application_secret = values.get('appsecret', 'notFound')
    oauth_url = values.get('oauth_url', 'notFound')

    processStartDate = try_strptime(values.get('begindate', '1911-01-01 00:00:00'),dt_formats_to_try)
    latestdate = try_strptime(values.get('begindate', '1911-01-01 00:00:00'),dt_formats_to_try)

    sns_arn_1 = values.get('sns_arn_l1', 'notFound')  # Self-trigger for continuation
    sns_arn_2 = values.get('sns_arn_l2', 'notFound')
    sns_arn_3 = values.get('sns_arn_l3', 'notFound')
    secret_arn = values.get('secret_arn', 'secretArnNotFound')

    partitionSize = int(values.get('partitionSize','5242880'))
    maxPartitionsPerFile = int(values.get('maxPartitions','9999'))
    UseFullFilePath = values.get('UseFullFilePath','True')

    token_credential = ClientSecretCredential(
        active_directory_tenant_id,
        active_directory_application_id,
        active_directory_application_secret
    )

    blob_service_client = BlobServiceClient(
        account_url=oauth_url,
        credential=token_credential
    )
    client = Client('sns')

    processed_count = 0
    
    # Process specific container or get next container
    if container_name:
        containers_to_process = [{'name': container_name}]
    else:
        all_containers = list(blob_service_client.list_containers(include_metadata=True))
        containers_to_process = all_containers

    for container in containers_to_process:
        if processed_count >= batch_size:
            # Trigger next batch
            next_values = values.copy()
            next_values['container_name'] = container['name']
            client.publish(
                TargetArn=sns_arn_1,
                Message=json.dumps({'default': json.dumps(next_values)}),
                MessageStructure='json'
            )
            break
            
        container_client = blob_service_client.get_container_client(container['name'])
        
        # Use pagination for blobs
        blob_iter = container_client.list_blobs()
        if continuation_token:
            blob_iter = container_client.list_blobs(marker=continuation_token)
            
        for blob in blob_iter:
            if processed_count >= batch_size:
                # Trigger continuation with token
                next_values = values.copy()
                next_values['container_name'] = container['name']
                next_values['continuation_token'] = blob.name
                client.publish(
                    TargetArn=sns_arn_1,
                    Message=json.dumps({'default': json.dumps(next_values)}),
                    MessageStructure='json'
                )
                return 'batch_complete'
                
            fileTime = try_strptime(blob.last_modified.strftime(dt_format_code),dt_formats_to_try)
            size = blob.size
            adaptiveCeiling = partitionSize * maxPartitionsPerFile
            
            if fileTime > latestdate:
                latestdate = fileTime

            if fileTime > processStartDate:
                if (size > partitionSize):
                    if(size > adaptiveCeiling):
                        partitionSize = int(math.ceil(size / adaptiveCeiling))
                    b = BlobInfo(container['name'], blob.name, UseFullFilePath, fileTime.strftime(dt_format_code), size, partitionSize, values, blob.content_settings)
                    client.publish(
                        TargetArn=sns_arn_3,
                        Message=json.dumps({'default': b.toJSON()}),
                        MessageStructure='json'
                    )
                else:
                    b = BlobInfo(container['name'], blob.name, UseFullFilePath, fileTime.strftime(dt_format_code), size, partitionSize, values, blob.content_settings)
                    client.publish(
                        TargetArn=sns_arn_2,
                        Message=json.dumps({'default': b.toJSON()}),
                        MessageStructure='json'
                    )
                    
            processed_count += 1

    # Update secret with latest date
    if latestdate > processStartDate:
        client = Client('secretsmanager')
        response = client.get_secret_value(SecretId=secret_arn)
        secret = response['SecretString']
        secret = secret.replace('"begindate":"' + values.get('begindate', '1911-01-01 00:00:00') + '"', '"begindate":"' + latestdate.strftime(dt_format_code) + '"')
        client.update_secret(SecretId=secret_arn, SecretString=secret)
        
    return 'success'
