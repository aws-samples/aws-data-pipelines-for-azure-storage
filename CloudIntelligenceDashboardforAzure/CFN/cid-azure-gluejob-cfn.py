# AWS Cloud Intelligence Dashboard for Azure Glue Script - CloudFormation

# Glue base
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

# Parameters fetched from System Manager Parameter Store
ssm_client = boto3.client('ssm')

var_account_type = ((ssm_client.get_parameter(Name="cidazure-var_account_type"))['Parameter']['Value'])
var_bucket = ((ssm_client.get_parameter(Name="cidazure-var_bucket"))['Parameter']['Value'])
var_date_format = ((ssm_client.get_parameter(Name="cidazure-var_date_format"))['Parameter']['Value'])
var_bulk_run = ((ssm_client.get_parameter(Name="cidazure-var_bulk_run"))['Parameter']['Value'])
var_error_folder = ((ssm_client.get_parameter(Name="cidazure-var_error_folder"))['Parameter']['Value'])
var_glue_database = ((ssm_client.get_parameter(Name="cidazure-var_glue_database"))['Parameter']['Value'])
var_glue_table = ((ssm_client.get_parameter(Name="cidazure-var_glue_table"))['Parameter']['Value'])
var_parquet_folder = ((ssm_client.get_parameter(Name="cidazure-var_parquet_folder"))["Parameter"]["Value"])
var_parquet_path = ((ssm_client.get_parameter(Name="cidazure-var_parquet_path"))["Parameter"]["Value"])
var_processed_folder = ((ssm_client.get_parameter(Name="cidazure-var_processed_folder"))['Parameter']['Value'])
var_processed_path = ((ssm_client.get_parameter(Name="cidazure-var_processed_path"))['Parameter']['Value'])
var_raw_folder = ((ssm_client.get_parameter(Name="cidazure-var_raw_folder"))['Parameter']['Value'])
var_raw_path = ((ssm_client.get_parameter(Name="cidazure-var_raw_path"))["Parameter"]["Value"])+((ssm_client.get_parameter(Name="cidazure-var_folderpath"))["Parameter"]["Value"])
SELECTED_TAGS = ((ssm_client.get_parameter(Name="cidazure-var_azuretags"))['Parameter']['Value']).split(", ")

# Copy Function
import concurrent.futures
def copy_s3_objects(source_bucket, source_folder, destination_bucket, destination_folder):
    s3_client = boto3.client('s3')
    def copy_object(obj):
        copy_source = {'Bucket': source_bucket, 'Key': obj['Key']}
        target_key = obj['Key'].replace(source_folder, destination_folder)
        s3_client.copy_object(Bucket=destination_bucket, Key=target_key, CopySource=copy_source, TaggingDirective='COPY')
        print("INFO: "f"Object copied: {obj['Key']}")
    # Get the list of files
    response = s3_client.list_objects(Bucket=source_bucket, Prefix=source_folder)
    objects = response.get('Contents', [])
    if objects:
        # Copy files using concurrent futures
        with concurrent.futures.ThreadPoolExecutor() as executor:
            executor.map(copy_object, objects)
        print("INFO: Copy process complete")
    else:
        print(("INFO: No files in {}, copy process skipped.").format(source_folder))

# Delete Function
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

# Bulk Run. Process only latest object for each month.
from datetime import datetime

if var_bulk_run == 'true':
    # Copy CSV files from raw to processed
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

    # Change bulk_run ssm parameter to false
    ssm_client.put_parameter(Name='cidazure-var_bulk_run',Value='false',Type='String',Overwrite=True)
else:
    print("INFO: Bulk run is set to {}, continuing with normal run".format(var_bulk_run))

# Read CSV files.
import os

try:
    df1 = spark.read.option("header","true").option("delimiter",",").option("escape", "\"").csv(var_raw_path)
except Exception as e:
    print("WARNING: Cannot read CSV file(s) in {}. Incorrect path or folder empty.".format(var_raw_path))
    print("ERROR: {}".format(e))
    raise e

# Create column Tags_map (transformed Tags column as map)
from pyspark.sql.functions import col, udf
from pyspark.sql.types import ArrayType, StringType, MapType
import json

def transform_to_map(resource_tags):
    if resource_tags: return dict(json.loads("{" + resource_tags + "}"))
    return ""
tagsTransformToMapUDF = udf(lambda x:transform_to_map(x), MapType(StringType(), StringType()))
df1 = df1.withColumn("Tags_map", tagsTransformToMapUDF(col("Tags")))

# Create columns per selected tag with values
for tag in SELECTED_TAGS:
    df1 = df1.withColumn("tag-"+tag, df1.Tags_map.getItem(tag))

# Identify account type parse dates and cast datatypes
from pyspark.sql.functions import to_date
from pyspark.sql.functions import col
from pyspark.sql.types import *

try:
    if var_account_type == "EA" or var_account_type == "MCA":
        # Rename Cost column to CostinBillingCurrency
        if "Cost" in df1.columns:
            df1 = df1.withColumnRenamed("Cost", "CostInBillingCurrency")
        df2 = df1.withColumn("DateParsed", to_date(df1.Date, var_date_format)) \
            .withColumn("BillingPeriodStartDateParsed", to_date(df1.BillingPeriodStartDate, var_date_format)) \
            .withColumn("BillingPeriodEndDateParsed", to_date(df1.BillingPeriodEndDate, var_date_format)) \
            .withColumn("BillingProfileId", col("BillingProfileId").cast(LongType())) \
            .withColumn("CostInBillingCurrency", col("CostInBillingCurrency").cast(DecimalType(21, 16))) \
            .withColumn("EffectivePrice", col("EffectivePrice").cast(DecimalType(21, 16))) \
            .withColumn("IsAzureCreditEligible", col("IsAzureCreditEligible").cast(BooleanType())) \
            .withColumn("PayGPrice", col("PayGPrice").cast(LongType())) \
            .withColumn("Quantity", col("Quantity").cast(DoubleType())) \
            .withColumn("UnitPrice", col("UnitPrice").cast(DoubleType()))

    if var_account_type == "PTAX":
        # Rename PreTaxCost column to CostinBillingCurrency
        df1 = df1.withColumnRenamed("PreTaxCost", "CostInBillingCurrency")
        df2 = df1.withColumn("DateParsed", to_date(df1.UsageDateTime, var_date_format)) \
            .withColumn("CostInBillingCurrency", col("CostInBillingCurrency").cast(DecimalType(21, 16))) \
            .withColumn("UsageQuantity", col("UsageQuantity").cast(DoubleType())) \
            .withColumn("ResourceRate", col("ResourceRate").cast(DoubleType()))
except Exception as e:
    # If the file(s) cannot be processed, move to the error folder
    copy_s3_objects(var_bucket, var_raw_folder, var_bucket, var_error_folder)
    delete_s3_folder(var_bucket, var_raw_folder)
    print("WARNING: Cannot parse columns. Error in CSV file(s). Moving to error folder")
    print("ERROR: {}".format(e))
    raise e

# Create partition column
from pyspark.sql.functions import trunc

df2 = df2.withColumn("Month", trunc(df2.DateParsed, "MM"))

# Parquet clean up to avoid duplication.
from pyspark.sql.functions import date_trunc

try:
    s3 = boto3.client('s3')
    response = s3.list_objects_v2(Bucket=var_bucket, Prefix=var_parquet_folder)
    if 'Contents' in response:
        id_months = df2.select(date_trunc("month", "Month")).distinct()
        new_months = [var_parquet_path + 'Month=' + f"{row[0].strftime('%Y-%m-%d')}" for row in id_months.collect()]
        # Remove Parquet files, older than 12 hours, that match the months identified above. Use 'retentionPeriod': 0.00069444444 for testing sets to 1 minute
        for path in new_months:
            glueContext.purge_s3_path(path, {'retentionPeriod': 0.00069444444})
    else:
        print("INFO: Parquet folder does not exist. No files to deduplicate")
except Exception as e:
    # If the file(s) cannot be processed move to error folder
    copy_s3_objects(var_bucket, var_raw_folder, var_bucket, var_error_folder)
    delete_s3_folder(var_bucket, var_raw_folder)
    print("WARNING: Cannot deduplicate. Error in CSV file(s). Moving to error folder")
    print("ERROR: {}".format(e))
    raise e

# Create parquet files and update glue catalog
from awsglue.dynamicframe import DynamicFrame

try:
    dyf3 = DynamicFrame.fromDF(df2, glueContext, "dyf3")
    sink = glueContext.getSink(connection_type="s3",path=(var_parquet_path),enableUpdateCatalog=True,partitionKeys=["Month"])
    sink.setFormat("glueparquet")
    sink.setCatalogInfo(catalogDatabase=(var_glue_database), catalogTableName=(var_glue_table))
    sink.writeFrame(dyf3)
except Exception as e:
    # If the file(s) cannot be processed move to error folder
    copy_s3_objects(var_bucket, var_raw_folder, var_bucket, var_error_folder)
    delete_s3_folder(var_bucket, var_raw_folder)
    print("WARNING: Cannot convert file(s) to parquet. Moving to error folder")
    print("ERROR: {}".format(e))
    raise e

# Copy CSV files from raw to processed
copy_s3_objects(var_bucket, var_raw_folder, var_bucket, var_processed_folder)

# Delete raw files
delete_s3_folder(var_bucket, var_raw_folder)

# Sample Jupyter Notebook tests
# df2.select('Date','DateParsed','BillingPeriodStartDate','BillingPeriodStartDateParsed','BillingPeriodEndDate','BillingPeriodEndDateParsed','Month','ResourceId','AdditionalInfo').show(10)
# df2.printSchema()
# from pyspark.sql.functions import sum as sum
# df2.select(sum(df2.CostInBillingCurrency)).show()