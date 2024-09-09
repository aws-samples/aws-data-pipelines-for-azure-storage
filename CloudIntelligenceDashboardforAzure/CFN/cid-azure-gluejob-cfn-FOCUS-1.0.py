# Cloud Intelligence Dashboard for Azure Glue Script - FOCUS Cost Export

### Glue base
import sys
import boto3
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

sc = SparkContext.getOrCreate()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

### Parameters fetched from Glue Job
from awsglue.utils import getResolvedOptions
args = getResolvedOptions(sys.argv, [
    'JOB_NAME', 'var_raw_path', 'var_parquet_path', 'var_processed_path',
    'var_glue_database', 'var_glue_table', 'var_bucket', 'var_raw_folder',
    'var_processed_folder', 'var_parquet_folder', 'var_folderpath',
    'var_account_type', 'var_bulk_run_ssm_name', 'var_error_folder', 'var_lambda01_name'
])
var_raw_path = args['var_raw_path']
var_parquet_path = args['var_parquet_path']
var_processed_path = args['var_processed_path']
var_glue_database = args['var_glue_database']
var_glue_table = args['var_glue_table']
var_bucket = args['var_bucket']
var_raw_folder = args['var_raw_folder']
var_processed_folder = args['var_processed_folder']
var_parquet_folder = args['var_parquet_folder']
var_folderpath = args['var_folderpath']
var_account_type = args['var_account_type']
var_bulk_run_ssm_name = args['var_bulk_run_ssm_name']
var_error_folder = args['var_error_folder']
var_lambda01_name = args['var_lambda01_name']
var_raw_fullpath = var_raw_path + var_folderpath

### Copy Function
import concurrent.futures
def copy_s3_objects(source_bucket, source_folder, destination_bucket, destination_folder):
    s3_client = boto3.client('s3')
    def copy_object(obj):
        copy_source = {'Bucket': source_bucket, 'Key': obj['Key']}
        target_key = obj['Key'].replace(source_folder, destination_folder)
        s3_client.copy_object(Bucket=destination_bucket, Key=target_key, CopySource=copy_source, TaggingDirective='COPY')
    # Get list of files
    response = s3_client.list_objects(Bucket=source_bucket, Prefix=source_folder)
    objects = response.get('Contents', [])
    if objects:
        # Copy files using concurrent futures
        with concurrent.futures.ThreadPoolExecutor() as executor:
            executor.map(copy_object, objects)
        print("INFO: Copy process complete")
    else:
        print(("INFO: No files in {}, copy process skipped.").format(source_folder))

### Delete Function
def delete_s3_folder(bucket, folder):
    s3_client = boto3.client('s3')
    response = s3_client.list_objects(Bucket=bucket, Prefix=folder)
    objects = response.get('Contents', [])
    if objects:
        delete_keys = [{'Key': obj['Key']} for obj in objects]
        s3_client.delete_objects(Bucket=bucket, Delete={'Objects': delete_keys})
        print("INFO: Delete process complete")
    else:
        print(("INFO: No files in {}, delete process skipped.").format(folder))

### Bulk Run - process latest object for each month
from datetime import datetime
ssm_client = boto3.client('ssm')
var_bulk_run = ssm_client.get_parameter(Name=var_bulk_run_ssm_name)['Parameter']['Value']
if var_bulk_run == 'true':
    print("INFO: Bulk run is set to {}, starting bulk run".format(var_bulk_run))
    # Delete manifest.json files from raw folder
    s3 = boto3.client('s3')
    response = s3.list_objects_v2(Bucket=var_bucket, Prefix=var_raw_folder)
    for obj in response.get('Contents', []):
        key = obj['Key']
        if key.endswith('manifest.json'):
            print(f"INFO: Deleting manifest file {key}")
            s3.delete_object(Bucket=var_bucket, Key=key)
    # Copy CSV from raw to processed
    copy_s3_objects(var_bucket, var_raw_folder, var_bucket, var_processed_folder)
    # Delete raw files
    delete_s3_folder(var_bucket, var_raw_folder)
    # Delete parquet files
    delete_s3_folder(var_bucket, var_parquet_folder)
    # Create dictionary to store latest modified file for each month
    s3 = boto3.client('s3')
    tag_key = 'lastmodified'
    response = s3.list_objects_v2(Bucket=var_bucket, Prefix=var_processed_folder)
    latest_files = {}
    for obj in response.get('Contents', []):
        key = obj['Key']
        if key.endswith('/'):
            continue
        parent_key = '/'.join(key.split('/')[:-1])
        tags = s3.get_object_tagging(Bucket=var_bucket, Key=key)['TagSet']
        for tag in tags:
            if tag['Key'] == tag_key:
                last_modified = tag['Value']
                # Convert last_modified datetime object
                dt_object = datetime.strptime(last_modified, '%Y-%m-%d %H:%M:%S')
                # Convert datetime object to timestamp
                timestamp = dt_object.timestamp()
                # Check current file is the latest modified file for the month
                if parent_key in latest_files:
                    if timestamp > latest_files[parent_key]['timestamp']:
                        latest_files[parent_key] = {'key': key, 'timestamp': timestamp}
                else:
                    latest_files[parent_key] = {'key': key, 'timestamp': timestamp}
    # Copy latest modified file for each month to raw folder
    for parent_key, file_info in latest_files.items():
        key = file_info['key']
        new_key = key.replace(var_processed_folder, var_raw_folder)
        copy_s3_objects(var_bucket, key, var_bucket, new_key)
    # Print objects in the raw bucket, allows for file identification if bulk run fails
    s3 = boto3.client('s3')
    objects = s3.list_objects(Bucket=var_bucket).get('Contents', [])
    print("INFO: Bulk run complete, latest files for each month:")
    for obj in objects:
        if obj['Key'].startswith(var_raw_folder):
            print(obj['Key'])
    # Disable multipart upload Lambda functions
    lambda_client = boto3.client('lambda')
    try:
        # Retrieve current environment variables
        function_name = var_lambda01_name
        current_config = lambda_client.get_function_configuration(FunctionName=function_name)
        environment = current_config.get('Environment', {})
        variables = environment.get('Variables', {})

        # Update partitionSize
        variables['partitionSize'] = '10737418240'

        # Update function configuration with the modified environment variables
        response = lambda_client.update_function_configuration(
            FunctionName = function_name,
            Environment = {'Variables': variables}
        )
        print("INFO: Lambda function configuration updated successfully.")
    except Exception as e:
        print("ERROR: {}".format(e))
        pass
    # Change bulk_run ssm parameter to false
    ssm_client.put_parameter(Name=var_bulk_run_ssm_name, Value='false', Type='String', Overwrite=True)

else:
    print("INFO: Bulk run is set to {}, continuing with normal run".format(var_bulk_run))

### Read CSV and append file_path column
import os
from pyspark.sql.functions import input_file_name

try:
    df1 = spark.read.option("header","true").option("delimiter",",").option("escape", "\"").csv(var_raw_fullpath)
    df1 = df1.withColumn("file_path", input_file_name())
except Exception as e:
    print("WARNING: Cannot read CSV file(s) in {}. Incorrect path or folder empty.".format(var_raw_fullpath))
    print("ERROR: {}".format(e))
    raise e

### Cast datatypes for FOCUS Specification 
### https://microsoft.github.io/finops-toolkit/data#-dataset-metadata

from pyspark.sql.functions import col, to_timestamp, date_format, to_date
from pyspark.sql.types import *

try:
        df2 = df1.withColumn("BilledCost", col("BilledCost").cast(DoubleType())) \
            .withColumn("BillingPeriodEnd", to_date(date_format(to_timestamp(col("BillingPeriodEnd"), "yyyy-MM-dd'T'HH:mm'Z'"), "yyyy-MM-dd"))) \
            .withColumn("BillingPeriodStart", to_date(date_format(to_timestamp(col("BillingPeriodStart"), "yyyy-MM-dd'T'HH:mm'Z'"), "yyyy-MM-dd"))) \
            .withColumn("ChargePeriodEnd", to_date(date_format(to_timestamp(col("ChargePeriodEnd"), "yyyy-MM-dd'T'HH:mm'Z'"), "yyyy-MM-dd"))) \
            .withColumn("ChargePeriodStart", to_date(date_format(to_timestamp(col("ChargePeriodStart"), "yyyy-MM-dd'T'HH:mm'Z'"), "yyyy-MM-dd"))) \
            .withColumn("ConsumedQuantity", col("ConsumedQuantity").cast(DoubleType())) \
            .withColumn("ContractedCost", col("ContractedCost").cast(DoubleType())) \
            .withColumn("ContractedUnitPrice", col("ContractedUnitPrice").cast(DoubleType())) \
            .withColumn("EffectiveCost", col("EffectiveCost").cast(DoubleType())) \
            .withColumn("ListCost", col("ListCost").cast(DoubleType())) \
            .withColumn("ListUnitPrice", col("ListUnitPrice").cast(DoubleType())) \
            .withColumn("PricingQuantity", col("PricingQuantity").cast(DoubleType())) \
            .withColumn("x_BilledCostInUsd", col("x_BilledCostInUsd").cast(DecimalType(17, 16))) \
            .withColumn("x_BilledUnitPrice", col("x_BilledUnitPrice").cast(DecimalType(23, 22))) \
            .withColumn("x_BillingExchangeRate", col("x_BillingExchangeRate").cast(DecimalType(17, 16))) \
            .withColumn("x_BillingExchangeRateDate", to_date(date_format(to_timestamp(col("x_BillingExchangeRateDate"), "yyyy-MM-dd'T'HH:mm'Z'"), "yyyy-MM-dd"))) \
            .withColumn("x_ContractedCostInUsd", col("x_ContractedCostInUsd").cast(DecimalType(23, 22))) \
            .withColumn("x_EffectiveCostInUsd", col("x_EffectiveCostInUsd").cast(DecimalType(17, 16))) \
            .withColumn("x_EffectiveUnitPrice", col("x_EffectiveUnitPrice").cast(DecimalType(23, 22))) \
            .withColumn("x_ListCostInUsd", col("x_ListCostInUsd").cast(DecimalType(17, 16))) \
            .withColumn("x_PricingBlockSize", col("x_PricingBlockSize").cast(DoubleType())) \
            .withColumn("x_ServicePeriodEnd", to_date(date_format(to_timestamp(col("x_ServicePeriodEnd"), "yyyy-MM-dd'T'HH:mm'Z'"), "yyyy-MM-dd"))) \
            .withColumn("x_ServicePeriodStart", to_date(date_format(to_timestamp(col("x_ServicePeriodStart"), "yyyy-MM-dd'T'HH:mm'Z'"), "yyyy-MM-dd")))
except Exception as e:
    # If the CSV cannot be processed move to error folder
    copy_s3_objects(var_bucket, var_raw_folder, var_bucket, var_error_folder)
    delete_s3_folder(var_bucket, var_raw_folder)
    print("WARNING: Cannot parse columns. Error in CSV file(s). Moved to error folder")
    print("ERROR: {}".format(e))
    raise e

### Surface Azure Tags
from pyspark.sql.functions import col, udf
from pyspark.sql.types import ArrayType, StringType, MapType
import json

# Function handle JSON or instances where curly braces are missing from tag column.
def transform_to_map(resource_tags):
    if resource_tags:
        if resource_tags.startswith('{'):
            return dict(json.loads(resource_tags))
        else:
            return dict(json.loads("{" + resource_tags + "}"))
# Transform Tags column as map)
tagsTransformToMapUDF = udf(lambda x:transform_to_map(x), MapType(StringType(), StringType()))
df2 = df2.withColumn("Tags", tagsTransformToMapUDF(col("Tags")))

### Create partition column
from pyspark.sql.functions import trunc

df2 = df2.withColumn("BILLING_PERIOD", trunc(df2.BillingPeriodStart, "MM"))

### Parquet clean up to avoid duplication.
from pyspark.sql.functions import date_trunc

try:
    s3 = boto3.client('s3')
    response = s3.list_objects_v2(Bucket=var_bucket, Prefix=var_parquet_folder)
    if 'Contents' in response:
        id_months = df2.select(date_trunc("month", "BILLING_PERIOD")).distinct()
        new_months = [var_parquet_path + 'BILLING_PERIOD=' + f"{row[0].strftime('%Y-%m-%d')}" for row in id_months.collect()]
        # Remove Parquet files, older than 12 hours, that match the months identified above. Use 'retentionPeriod': 0.00069444444 for testing sets to 1 minute
        for path in new_months:
            glueContext.purge_s3_path(path, {'retentionPeriod': 0.00069444444})
    else:
        print("INFO: Parquet folder does not exist. No files to deduplicate")
except Exception as e:
    # If CSV cannot be processed move to error folder
    copy_s3_objects(var_bucket, var_raw_folder, var_bucket, var_error_folder)
    delete_s3_folder(var_bucket, var_raw_folder)
    print("WARNING: Cannot deduplicate. Error in CSV file(s). Moved to error folder")
    print("ERROR: {}".format(e))
    raise e

### Create parquet files and update glue catalog
from awsglue.dynamicframe import DynamicFrame

try:
    dyf3 = DynamicFrame.fromDF(df2, glueContext, "dyf3")
    sink = glueContext.getSink(connection_type="s3",path=(var_parquet_path),enableUpdateCatalog=True,partitionKeys=["BILLING_PERIOD"])
    sink.setFormat("glueparquet")
    sink.setCatalogInfo(catalogDatabase=(var_glue_database), catalogTableName=(var_glue_table))
    sink.writeFrame(dyf3)
except Exception as e:
    # If the CSV cannot be processed move to error folder
    copy_s3_objects(var_bucket, var_raw_folder, var_bucket, var_error_folder)
    delete_s3_folder(var_bucket, var_raw_folder)
    print("WARNING: Cannot convert file(s) to parquet. Moved to error folder if normal run")
    print("ERROR: {}".format(e))
    raise e

### Copy CSV from raw to processed
copy_s3_objects(var_bucket, var_raw_folder, var_bucket, var_processed_folder)

### Delete CSV from raw
delete_s3_folder(var_bucket, var_raw_folder)

### Sample Jupyter Notebook tests
# df1.select('ChargePeriodEnd','BillingPeriodStart','BillingPeriodEnd','ChargeDescription','BilledCost','Tags','file_path','BILLING_PERIOD').show(100)
# df1.printSchema()