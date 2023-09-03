import json
from boto3 import client as Client

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
    return {
        'statusCode': 200,
        'body': json.dumps(response)
    }
