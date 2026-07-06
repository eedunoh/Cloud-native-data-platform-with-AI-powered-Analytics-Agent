-- THIS SQL FILE WILL BE EXECUTED MANUALLY, preferably ONE BLOCK AFTER THE OTHER

-- Warehouse, database, schemas and others were created initially in file '01_.sql'
USE WAREHOUSE data_platform_wh;
USE ROLE accountadmin;
USE SCHEMA data_platform_db.raw;


-- Create S3 storage integration. 
-- The modern and secure way to connect/allow Snowflake's Snowpipe access to AWS' S3 buckets is through AWS IAM Role and policies. An alternative is the AWS access key + secret which is quite risky.
-- The storage integration is just a named object inside snowflake that holds the trust details.


-- On AWS, create an IAM ROLE and add these;
-- Here is Snlwflake's Guide: https://docs.snowflake.com/en/user-guide/data-load-s3-config-storage-integration

-- We need the ARN of this IAM Role to complete our setup on Snowflake. 
-- We will update this IAM Role later with more information.

  -- {
  --   Action    = "sts:AssumeRole"
  --   Effect    = "Allow"
  --   Principal = {
  --     AWS = "*"                  # Generic placeholder. Use this to create the IAM Role and update later with the actual STORAGE_AWS_IAM_USER_ARN when generated.
  --   }
  --   Condition = {
  --     StringEquals = {
  --       "sts:ExternalId" = "*"   # Generic placeholder. Use this to create the IAM Role and update later with the actual YOUR_STORAGE_AWS_EXTERNAL_ID when generated.
  --     }
  --   }
  -- }


-- In the IAM policy, add these;

 -- "Version": "2012-10-17",
 -- "Statement": [
 --     {
 --       "Effect": "Allow",
 --       "Action": [
 --            "s3:GetObject",
 --            "s3:GetObjectVersion",
 --            "s3:ListBucket",
 --            "s3:GetBucketLocation"
 --           ],
 --       "Resource" = [
                      -- "${aws_s3_bucket.<s3_bucket>.arn}",
                      -- "${aws_s3_bucket.<s3_bucket>.arn}/*",
                    -- ]
 --     },
    
-- Attach the IAM policy to the IAM ROLE
-- Apply changes and generate the IAM ROLE ARN. 
-- Add the AWS generated Snowflake IAM ROLE ARN to the setup below



-- Create the storage integration object
CREATE STORAGE INTEGRATION IF NOT EXISTS s3_integration
    TYPE = EXTERNAL_STAGE
    STORAGE_PROVIDER = 'S3'
    ENABLED = TRUE
    STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::337909745504:role/snowflake_iam_role'
    STORAGE_ALLOWED_LOCATIONS = (
        's3://data-platform-batch-processed-data-bucket/',
        's3://data-platform-streamed-data-bucket',
        's3://ai-document-extracts-bucket/'
    );


-- View and copy out the integration details (STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID)
DESC INTEGRATION s3_integration;

-- These are needed to update the AWS IAM role trust policy:
-- STORAGE_AWS_IAM_USER_ARN – a special user identity inside Snowflake’s own AWS account.
-- STORAGE_AWS_EXTERNAL_ID – a unique secret string that prevents other people from impersonating you.



-- Update the AWS IAM ROLE with the STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID generated on Snowlake

  -- {
  --   Action    = "sts:AssumeRole"
  --   Effect    = "Allow"
  --   Principal = {
  --     AWS = "YOUR_STORAGE_AWS_IAM_USER_ARN"
  --   }
  --   Condition = {
  --     StringEquals = {
  --       "sts:ExternalId" = "YOUR_STORAGE_AWS_EXTERNAL_ID"
  --     }
  --   }
  -- }



-- On Snowflakke, Verify the integration is correctly configured
DESC INTEGRATION s3_integration;



-- Create a file formats for JSON and PARQUET files stored in S3
-- IGNORE_UTF8_ERRORS = TRUE Prevents the data ingestion from failing if the source data contains malformed UTF-8 characters
-- STRIP_OUTER_ARRAY = TRUE tells Snowflake to remove the top‑level square brackets from a JSON file and treat each element inside the array as a separate row. If this is absent, Snowflake stores all elements/rows in a list of dicts and place them in a single row which may be difficult to extract during the data cleaning stage.
CREATE FILE FORMAT IF NOT EXISTS json_format
    TYPE = 'JSON'
    IGNORE_UTF8_ERRORS = TRUE
    STRIP_OUTER_ARRAY = TRUE;


CREATE FILE FORMAT IF NOT EXISTS parquet_format
    TYPE = 'PARQUET';



-- Create external stages pointing to the various S3 buckets and prefixes. A stage in Snowflake is specifically a pointer to an external location
-- I prefer to use different stages and snowpipes for the varioys prefixes as AGAINST using one stage and snowpipe per bucket (for all prefix in that bucket).
-- The Reason for this is because: updating one prefix pipeline's logic does not risk disrupting or breaking the ingest process for other piplines, it's easy to apply unique schemas, file formats, and COPY INTO logic to each specific prefix and Finally You can assign different Snowflake virtual warehouses to specific pipes to isolate compute costs.

CREATE STAGE IF NOT EXISTS raw_stage_streamed_sales
    URL = 's3://data-platform-streamed-data-bucket/'
    STORAGE_INTEGRATION = s3_integration
    FILE_FORMAT = parquet_format;

CREATE STAGE IF NOT EXISTS raw_stage_batch_stores
    URL = 's3://data-platform-batch-processed-data-bucket/stores/'
    STORAGE_INTEGRATION = s3_integration
    FILE_FORMAT = json_format;


CREATE STAGE IF NOT EXISTS raw_stage_batch_products
    URL = 's3://data-platform-batch-processed-data-bucket/products/'
    STORAGE_INTEGRATION = s3_integration
    FILE_FORMAT = json_format;


CREATE STAGE IF NOT EXISTS raw_stage_batch_exchange_rates
    URL = 's3://data-platform-batch-processed-data-bucket/exchange_rates/'
    STORAGE_INTEGRATION = s3_integration
    FILE_FORMAT = json_format;


CREATE STAGE IF NOT EXISTS raw_stage_batch_customers
    URL = 's3://data-platform-batch-processed-data-bucket/customers/'
    STORAGE_INTEGRATION = s3_integration
    FILE_FORMAT = json_format;


CREATE STAGE IF NOT EXISTS raw_stage_batch_data_dictionary
    URL = 's3://data-platform-batch-processed-data-bucket/data_dictionary/'
    STORAGE_INTEGRATION = s3_integration
    FILE_FORMAT = json_format;


CREATE STAGE IF NOT EXISTS raw_stage_ai_document_extracts
    URL = 's3://ai-document-extracts-bucket/'
    STORAGE_INTEGRATION = s3_integration
    FILE_FORMAT = json_format;




-- Create raw tables
-- Here is why I chose VARIANT over Typed columns: 
-- Events might have a stable schema now, but if new fields are added later (e.g., discount, campaign_id), a typed table would break or require an ALTER TABLE but VARIANT adapt dynamically.

-- VARIANT accepts any schema, so files from different prefixes can coexist without breaking the pipe (that is if you used one stage/snowpipe per bucket). Typed columns would force you to create separate tables/pipes for each schema or maintain a fragile superset of all columns.

-- dbt handles the transformations: In dbt, you flatten the VARIANT into clean, typed Silver tables using SQL. This separates ingestion (no‑fuss, no‑maintenance) from business logic (version‑controlled, testable). The raw layer stays simple; all schema enforcement and evolution happens safely inside your dbt models.

CREATE TABLE IF NOT EXISTS data_platform_db.raw.streamed_sales(
    raw_data VARIANT,
    source_file STRING,
    ingested_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
    );

CREATE TABLE IF NOT EXISTS data_platform_db.raw.stores(
    raw_data VARIANT,
    source_file STRING,
    ingested_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
    );

CREATE TABLE IF NOT EXISTS data_platform_db.raw.products(
    raw_data VARIANT,
    source_file STRING,
    ingested_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
    );

CREATE TABLE IF NOT EXISTS data_platform_db.raw.exchange_rates(
    raw_data VARIANT,
    source_file STRING,
    ingested_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
    );

CREATE TABLE IF NOT EXISTS data_platform_db.raw.customers(
    raw_data VARIANT,
    source_file STRING,
    ingested_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
    );

CREATE TABLE IF NOT EXISTS data_platform_db.raw.data_dictionary(
    raw_data VARIANT,
    source_file STRING,
    ingested_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
    );

CREATE TABLE IF NOT EXISTS data_platform_db.raw.ai_document_extracts(
    raw_data VARIANT,
    source_file STRING,
    ingested_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
    );




-- Create the SnowPipes for all stages and tables

-- When you have a raw table with three columns – one for the file’s data (raw_data VARIANT), one for the file’s name (source_file STRING) and one for (ingested_at TIMESTAMP_NTZ), you must use a subquery inside COPY INTO to tell Snowflake exactly what goes into each column.
-- Also, Parquet has many columns; Snowflake can’t collapse them into a single VARIANT unless you explicitly select $1 (the whole row).


-- BASICALLY:
-- $1 → the entire raw data row/document, stored as a VARIANT. For JSON it's the whole document; for Parquet it's the whole row collapsed into a VARIANT. That goes into the raw_data column.
-- METADATA$FILENAME → the full S3 key of the file being loaded, stored as STRING. It goes into the source_file column.
-- Snowflake sees that ingested_at is not added to copy into, but it has a default value (CURRENT_TIMESTAMP()), so it simply uses that default for every row. No error occurs.


-- So in SUMMARY:
-- For Parquet: Even if your defined table has a single raw_data VARIANT column and is no extra metadata column. Snowflake can't automatically convert parquet's multiple columns into one VARIANT. So its advisable to always use a Subquery: COPY INTO db.table(column x, column y) FROM (SELECT $1, METADATA$FILENAME FROM @stage).
-- For Json: If no extra metadata column in the defined raw table, JSON’s natural output is one VARIANT column so you DON'T need a subquery. A simple COPY INTO command is good (COPY INTO db.table(column x) FROM stage).
-- For Json: If there is an extra metadata column in the defined raw table, JSON’s natural output is one VARIANT column so you will need a subquery like in the case of parquet.


CREATE PIPE IF NOT EXISTS raw_stream_pipe
    AUTO_INGEST = TRUE
    AS
    COPY INTO data_platform_db.raw.streamed_sales (raw_data, source_file)
    FROM (
        SELECT $1, METADATA$FILENAME
        FROM @raw_stage_streamed_sales
    )
    FILE_FORMAT = parquet_format;


CREATE PIPE IF NOT EXISTS raw_stores_pipe
    AUTO_INGEST = TRUE
    AS
    COPY INTO data_platform_db.raw.stores (raw_data, source_file)
    FROM (
        SELECT $1, METADATA$FILENAME
        FROM @raw_stage_batch_stores
    )
    FILE_FORMAT = json_format;


CREATE PIPE IF NOT EXISTS raw_products_pipe
    AUTO_INGEST = TRUE
    AS
    COPY INTO data_platform_db.raw.products (raw_data, source_file)
    FROM (
        SELECT $1, METADATA$FILENAME
        FROM @raw_stage_batch_products
    )
    FILE_FORMAT = json_format;


CREATE PIPE IF NOT EXISTS raw_exchange_rates_pipe
    AUTO_INGEST = TRUE
    AS
    COPY INTO data_platform_db.raw.exchange_rates (raw_data, source_file)
    FROM (
        SELECT $1, METADATA$FILENAME
        FROM @raw_stage_batch_exchange_rates
    )
    FILE_FORMAT = json_format;


CREATE PIPE IF NOT EXISTS raw_customers_pipe
    AUTO_INGEST = TRUE
    AS
    COPY INTO data_platform_db.raw.customers (raw_data, source_file)
    FROM (
        SELECT $1, METADATA$FILENAME
        FROM @raw_stage_batch_customers
    )
    FILE_FORMAT = json_format;


CREATE PIPE IF NOT EXISTS raw_data_dictionary_pipe
    AUTO_INGEST = TRUE
    AS
    COPY INTO data_platform_db.raw.data_dictionary (raw_data, source_file)
    FROM (
        SELECT $1, METADATA$FILENAME
        FROM @raw_stage_batch_data_dictionary
    )
    FILE_FORMAT = json_format;


CREATE PIPE IF NOT EXISTS raw_ai_document_extracts_pipe
    AUTO_INGEST = TRUE
    AS
    COPY INTO data_platform_db.raw.ai_document_extracts (raw_data, source_file)
    FROM (
        SELECT $1, METADATA$FILENAME
        FROM @raw_stage_ai_document_extracts
    )
    FILE_FORMAT = json_format;



-- Generate the SQS ARN. 
-- Look at the notification_channel column; it will show the SQS ARN.

-- This will be used in the S3 Event Notification configuration. The S3 Event Notifications can be at the bucket or prefix levels
-- Snowflake will be notified whenever there is a "s3:ObjectCreated:*" event in the S3/prefix.

-- When you configure an auto-ingest Snowpipe, Snowflake automatically generates an (ONLY 1) Amazon SQS queue to handle file notifications for ALL PIPES
-- Because Snowflake provisions one dedicated SQS queue per region for your entire account, every automated Snowpipe created on stages in that same region will display the exact same notification channel ARN.
-- ALWAYS CONFIRM ALL OF THEM HAVE THE SAME ARN. DON'T ASSUME

SHOW PIPES;

-- Create the S3 Event Notification and add the SQS ARN.




select *
-- from data_platform_db.raw.streamed_sales
-- FROM data_platform_db.raw.data_dictionary
-- from data_platform_db.raw.customers
-- from data_platform_db.raw.stores
from data_platform_db.raw.ai_document_extracts
-- FROM data_platform_db.raw.streamed_sales;