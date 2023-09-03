import json
from boto3 import client as Client
from datetime import datetime
from os import environ

dt_format_code = '%Y-%m-%d %H:%M:%S'

# Function to trigger qualification step
def try_strptime(s, fmts=['%d-%b-%y','%m/%d/%Y','%Y-%m-%d %H:%M:%S','%Y%m%d']):
    for fmt in fmts:
        try:
            return datetime.strptime(s, fmt)
        except:
            continue

    return None

# Grab specific tag values for a SecretsManager secret description
def get_first_tag_value_for_secretDescription_for_key(secretDescription, key):
    tags = secretDescription['Tags']
    nameTag = ([tag for tag in tags if tag['Key'] == key ])[0].get('Value')
    return nameTag

def lambda_handler(event, context):
    secret_arn = environ['secret']
    client = Client('secretsmanager')
    response = client.get_secret_value(
        SecretId = secret_arn
    )
    secrets = json.loads(response['SecretString'])
    # Check if isactive secret equals True
    processActive = secrets.get('isactive','notFound')

    if processActive :
        # Check if date greater than begindate secret 
        processStartDate = try_strptime(secrets.get('begindate','1911-01-01 00:00:00'),['%d-%b-%y','%m/%d/%Y','%Y-%m-%d %H:%M:%S','%Y%m%d'])
        # Create json payload
        if processStartDate < datetime.today():
            description = client.describe_secret(
                SecretId = secret_arn
            )
            # TODO: If sns_arn not found -> throw exception
            sns_arn = secrets.get('sns_arn_l1','notFound')
            secrets['secret_arn'] = secret_arn
            secrets['oauth_url'] = secrets.get('bloburl','bloburlNotFound')
            secrets['partitionSize'] = environ['partitionSize']
            secrets['maxPartitionsPerFile'] = environ['maxPartitionsPerFile']
            secrets['UseFullFilePath'] = environ['UseFullFilePath']
            secrets['bucket_name'] = secrets.get('bucket_name','bucketNotFound')

            message = secrets
            client = Client('sns')
            response = client.publish(
                TargetArn=sns_arn,
                Message=json.dumps({'default': json.dumps(message)}),
                MessageStructure='json'
            )
            print('Executing Azure Blob Copy Process')

        else :
            print('Azure Blob Copy Process is disabled or no data to process')
    return 'SUCCESS'
