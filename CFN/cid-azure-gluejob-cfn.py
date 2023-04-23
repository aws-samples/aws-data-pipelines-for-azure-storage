# AWS Cloud Intelligence Dashboard for Azure Glue Script - CloudFormation

# Parameters fetched from System Manager Parameter Store
import boto3
ssm_client = boto3.client('ssm')
var_source_path = ((ssm_client.get_parameter(Name="cidazure-var_source_path"))["Parameter"]["Value"])+((ssm_client.get_parameter(Name="cidazure-var_folderpath"))["Parameter"]["Value"])
var_destination_path = ((ssm_client.get_parameter(Name="cidazure-var_destination_path"))["Parameter"]["Value"])
var_processed_path = ((ssm_client.get_parameter(Name="cidazure-var_processed_path"))['Parameter']['Value'])
var_glue_database = ((ssm_client.get_parameter(Name="cidazure-var_glue_database"))['Parameter']['Value'])
var_glue_table = ((ssm_client.get_parameter(Name="cidazure-var_glue_table"))['Parameter']['Value'])
var_bucketname = ((ssm_client.get_parameter(Name="cidazure-var_bucketname"))['Parameter']['Value'])
var_source = ((ssm_client.get_parameter(Name="cidazure-var_source"))['Parameter']['Value'])
var_target = ((ssm_client.get_parameter(Name="cidazure-var_target"))['Parameter']['Value'])
var_dateformat = ((ssm_client.get_parameter(Name="cidazure-var_dateformat"))['Parameter']['Value'])
var_accounttype = ((ssm_client.get_parameter(Name="cidazure-var_accounttype"))['Parameter']['Value'])
SELECTED_TAGS = ((ssm_client.get_parameter(Name="cidazure-var_azuretags"))['Parameter']['Value']).split(", ")

# Glue base
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

sc = SparkContext.getOrCreate()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

# Read CSV files. Raise exception and stop script gracefully if azurecidraw folder is empty
import os
try:
    df1 = spark.read.option("header","true").option("delimiter",",").option("escape", "\"").csv(var_source_path)
except Exception as e:
    print("Can not import files from {}, folder rather empty or other issue occurred".format(var_source_path))
    print("Exception message: {}".format(e))
    os._exit(0)

# Create column Tags_map (transformed Tags column as map) # TODO: Drop columns Tags and Tags_map as not needed further
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

if var_accounttype=="EA" or var_accounttype=="MCA":
    if ("Cost" in df1.columns): cost_column = "Cost"
    else: cost_column = "CostInBillingCurrency"
    df2 = df1.withColumn("DateParsed",to_date(df1.Date,(var_dateformat))) \
             .withColumn("BillingPeriodStartDateParsed",to_date(df1.BillingPeriodStartDate,(var_dateformat))) \
             .withColumn("BillingPeriodEndDateParsed",to_date(df1.BillingPeriodEndDate,(var_dateformat))) \
             .withColumn("BillingProfileId",col("BillingProfileId").cast(LongType())) \
             .withColumn(cost_column,col(cost_column).cast(DecimalType(21,16))) \
             .withColumn("EffectivePrice",col("EffectivePrice").cast(DecimalType(21,16))) \
             .withColumn("IsAzureCreditEligible",col("IsAzureCreditEligible").cast(BooleanType())) \
             .withColumn("PayGPrice",col("PayGPrice").cast(LongType())) \
             .withColumn("Quantity",col("Quantity").cast(DoubleType())) \
             .withColumn("UnitPrice",col("UnitPrice").cast(DoubleType())) \

# Identify account type (PTAX) and cast datatypes
if var_accounttype=="PTAX" :
    df2 = df1.withColumn("DateParsed", to_date(df1.UsageDateTime, (var_dateformat))) \
        .withColumn("PreTaxCost", col("PreTaxCost").cast(DecimalType(21, 16))) \
        .withColumn("UsageQuantity", col("UsageQuantity").cast(DoubleType())) \
        .withColumn("ResourceRate", col("ResourceRate").cast(DoubleType())) \

# Create partition column
from pyspark.sql.functions import trunc
df2 = df2.withColumn("Month", trunc(df2.DateParsed, "MM"))

# Create parquet files and update glue catalog
from awsglue.dynamicframe import DynamicFrame
dyf3 = DynamicFrame.fromDF(df2, glueContext, "dyf3")
sink = glueContext.getSink(
    connection_type="s3",
    path=(var_destination_path),
    enableUpdateCatalog=True,
    partitionKeys=["Month"])
sink.setFormat("glueparquet")
sink.setCatalogInfo(catalogDatabase=(var_glue_database), catalogTableName=(var_glue_table))
sink.writeFrame(dyf3)

# Remove old files from current month azureparquetraw (removes all files older than 1 hour - presumably files are uploaded daily)
glueContext.purge_s3_path(var_destination_path + df2.first()["Month"], {"retentionPeriod": 1})

# Move CSV files to processed folder 
import boto3
for obj in boto3.resource('s3').Bucket(var_bucketname).objects.filter(Prefix=var_source):
    source_filename = (obj.key).split(f'{var_source}/')[-1]
    copy_source = {'Bucket': var_bucketname,'Key': obj.key}
    boto3.resource('s3').meta.client.copy(copy_source, var_bucketname, f'{var_target}/{source_filename}')

# Delete raw folder
boto3.resource('s3').Bucket(var_bucketname).objects.filter(Prefix=f'{var_source}/').delete()

# Sample Jupyter Notebook tests
# print(processedfiles)
# df2.select('Date','DateParsed','BillingPeriodStartDate','BillingPeriodStartDateParsed','BillingPeriodEndDate','BillingPeriodEndDateParsed','Month','ResourceId','AdditionalInfo').show(10)
# df2.printSchema()
# from pyspark.sql.functions import sum as sum
# df2.select(sum(df2.CostInBillingCurrency)).show()