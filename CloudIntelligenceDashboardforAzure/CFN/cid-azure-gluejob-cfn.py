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

# Functions
def move_to_error_folder(var_bucket, var_raw_folder, var_error_folder):
    s3 = boto3.resource('s3')
    bucket = s3.Bucket(var_bucket)
    # Copy file(s) to error folder
    for obj in bucket.objects.filter(Prefix=var_raw_folder):
        copy_source = {'Bucket': var_bucket, 'Key': obj.key}
        target_key = obj.key.replace(var_raw_folder, var_error_folder)
        s3.Object(var_bucket, target_key).copy_from(CopySource=copy_source, TaggingDirective='COPY')
    # Delete file(s) from raw folder
    bucket.objects.filter(Prefix=var_raw_folder).delete()

# Bulk Run. Process only latest object for each month.
from datetime import datetime

if var_bulk_run == 'true':
    s3 = boto3.resource('s3')
    # Copy CSV files from raw to processed
    for obj in s3.Bucket(var_bucket).objects.filter(Prefix=var_raw_folder):
        copy_source = {'Bucket': var_bucket, 'Key': obj.key}
        target_key = obj.key.replace(var_raw_folder, var_processed_folder)
        s3.Object(var_bucket, target_key).copy_from(CopySource=copy_source, TaggingDirective='COPY')
    # Delete raw files
    s3.Bucket(var_bucket).objects.filter(Prefix=var_raw_folder).delete()
    # Delete parquet files
    s3.Bucket(var_bucket).objects.filter(Prefix=var_parquet_folder).delete()
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
        s3.copy_object(Bucket=var_bucket, CopySource={'Bucket': var_bucket, 'Key': key}, Key=new_key)
    # Change bulk_run ssm parameter to false
    ssm_client.put_parameter(Name='cidazure-var_bulk_run',Value='false',Type='String',Overwrite=True)
else:
    print("INFO: Bulk run is set to {}, continuing with normal run".format(var_bulk_run))

# Read CSV files.
import os

try:
    df1 = spark.read.option("header","true").option("delimiter",",").option("escape", "\"").csv(var_raw_path)
except Exception as e:
    print("WARNING: Cannot read CSV file(s) in {}. Incorrect path or folder empty. Ending gracefully".format(var_raw_path))
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

# Parse date columns and cast non string datatypes. Identify account type (EA+MCA) and cast datatypes
from pyspark.sql.functions import to_date
from pyspark.sql.functions import col
from pyspark.sql.types import *

try:
    if var_account_type == "EA" or var_account_type == "MCA":
        if "Cost" in df1.columns:
            cost_column = "Cost"
        else:
            cost_column = "CostInBillingCurrency"
        df2 = df1.withColumn("DateParsed", to_date(df1.Date, var_date_format)) \
            .withColumn("BillingPeriodStartDateParsed", to_date(df1.BillingPeriodStartDate, var_date_format)) \
            .withColumn("BillingPeriodEndDateParsed", to_date(df1.BillingPeriodEndDate, var_date_format)) \
            .withColumn("BillingProfileId", col("BillingProfileId").cast(LongType())) \
            .withColumn(cost_column, col(cost_column).cast(DecimalType(21, 16))) \
            .withColumn("EffectivePrice", col("EffectivePrice").cast(DecimalType(21, 16))) \
            .withColumn("IsAzureCreditEligible", col("IsAzureCreditEligible").cast(BooleanType())) \
            .withColumn("PayGPrice", col("PayGPrice").cast(LongType())) \
            .withColumn("Quantity", col("Quantity").cast(DoubleType())) \
            .withColumn("UnitPrice", col("UnitPrice").cast(DoubleType()))

    # Identify account type (PTAX) and cast datatypes
    if var_account_type == "PTAX":
        df2 = df1.withColumn("DateParsed", to_date(df1.UsageDateTime, var_date_format)) \
            .withColumn("PreTaxCost", col("PreTaxCost").cast(DecimalType(21, 16))) \
            .withColumn("UsageQuantity", col("UsageQuantity").cast(DoubleType())) \
            .withColumn("ResourceRate", col("ResourceRate").cast(DoubleType()))
except Exception as e:
    # If the file(s) cannot be processed, move to the error folder
    move_to_error_folder(var_bucket, var_raw_folder, var_error_folder)
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
    move_to_error_folder(var_bucket, var_raw_folder, var_error_folder)
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
    move_to_error_folder(var_bucket, var_raw_folder, var_error_folder)
    print("WARNING: Cannot convert file(s) to parquet. Moving to error folder")
    print("ERROR: {}".format(e))
    raise e

# Copy CSV files from raw to processed
s3 = boto3.resource('s3')
for obj in s3.Bucket(var_bucket).objects.filter(Prefix=var_raw_folder):
    copy_source = {'Bucket': var_bucket, 'Key': obj.key}
    target_key = obj.key.replace(var_raw_folder, var_processed_folder)
    s3.Object(var_bucket, target_key).copy_from(CopySource=copy_source, TaggingDirective='COPY')

# Delete raw files
s3.Bucket(var_bucket).objects.filter(Prefix=var_raw_folder).delete()

# Sample Jupyter Notebook tests
# df2.select('Date','DateParsed','BillingPeriodStartDate','BillingPeriodStartDateParsed','BillingPeriodEndDate','BillingPeriodEndDateParsed','Month','ResourceId','AdditionalInfo').show(10)
# df2.printSchema()
# from pyspark.sql.functions import sum as sum
# df2.select(sum(df2.CostInBillingCurrency)).show()