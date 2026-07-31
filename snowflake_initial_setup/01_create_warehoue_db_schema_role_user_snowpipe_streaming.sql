-- Data platform setup: warehouse, database, schemas, tables, roles, and users
-- Co-authored with CoCo
-- THIS SQL FILE WILL BE EXECUTED MANUALLY

USE ROLE ACCOUNTADMIN;

-- Creae the warehouse
-- Since this is a development stage, I will de-activate some parameters listed below;
-- AUTO_SUSPEND = 60 means shut down after 60 seconds of inactivity
-- AUTO_RESUME = TRUE means start automatically when a query runs
-- These saves credits

CREATE WAREHOUSE IF NOT EXISTS data_platform_wh
    WAREHOUSE_SIZE = 'X-SMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;

-- Create database
CREATE DATABASE IF NOT EXISTS data_platform_db;


-- There will be 3 layers to represent the medallion architecture, raw (bronze), silver and gold.
-- Create schemas for each layer
-- RAW: Raw data loaded directly from AWS S3
-- SILVER: Transformed and cleaned data
-- GOLD: aggregated, business ready data

USE DATABASE data_platform_db;

CREATE SCHEMA IF NOT EXISTS data_platform_db.raw;
CREATE SCHEMA IF NOT EXISTS data_platform_db.silver;
CREATE SCHEMA IF NOT EXISTS data_platform_db.gold;




-- Create raw tables using the ACCOUNTADMIN

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





-- Create a dedicated role to be used by DBT and Kafka consumer
-- Best practice — never use ACCOUNTADMIN for day to day operations
CREATE ROLE IF NOT EXISTS data_platform_role;
CREATE ROLE IF NOT EXISTS kafka_streamer_role;




-- Also grant dataplatform and kafka_streamer_role roles to ACCOUNTADMIN. 
-- Without this permission, ACCOUNTADMIN will not be able to carry out any action on tables created by dataplatform and kafka_streamer roles despite ACCOUNTADMIN role being a higher level role.
-- So this command literally grants ACCOUNTADMIN all permissions givent to data_platform role.
GRANT ROLE data_platform_role TO ROLE ACCOUNTADMIN;
GRANT ROLE kafka_streamer_role TO ROLE ACCOUNTADMIN;




-- These roles can use the data_platform_wh warehouse
GRANT USAGE ON WAREHOUSE data_platform_wh TO ROLE data_platform_role;
GRANT USAGE ON WAREHOUSE data_platform_wh TO ROLE kafka_streamer_role;


-- These roles can use the data_platform_db database
GRANT USAGE ON DATABASE data_platform_db TO ROLE data_platform_role;
GRANT USAGE ON DATABASE data_platform_db TO ROLE kafka_streamer_role;




-- Create a dedicated data_platform user
CREATE USER IF NOT EXISTS data_platform_user
    PASSWORD = 'dataBaseUser6654!&'
    DEFAULT_ROLE = data_platform_role
    DEFAULT_WAREHOUSE = data_platform_wh
    DEFAULT_NAMESPACE = data_platform_db.raw;


-- Create a dedicated kafka steamer user
CREATE USER IF NOT EXISTS kafka_streamer_user
    PASSWORD = 'KafkaUser6654!&'
    DEFAULT_ROLE = kafka_streamer_role
    DEFAULT_WAREHOUSE = data_platform_wh
    DEFAULT_NAMESPACE = data_platform_db.raw;




-- Grant roles to the users & users assume the roles
GRANT ROLE data_platform_role TO USER data_platform_user;
GRANT ROLE kafka_streamer_role TO USER kafka_streamer_user;





-- After creating kafka_streamer_user (which I will use to stream data using snowpipe streaming), I need to Set the public key for key-pair authentication.
-- Follow this documentation: https://docs.snowflake.com/en/user-guide/snowpipe-streaming/snowpipe-streaming-high-performance-getting-started
-- You will also need the rsa_key.p8 which will be attached to the snowflake connector in the python SDK.

-- Use this to generate the private and public keys on your PC's local terminal:
-- openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8 -nocrypt openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub

ALTER USER kafka_streamer_user SET RSA_PUBLIC_KEY='MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0HlWgI8VeXcauGLAGM/SJuMYf9qj+olAkXbrkg9OEIz/fQby/8uqLxKTg0J5dPuh/cyIZLdMKTp0B9zJHSc7TtW7VNMpQqnX/nnpjwzzsS8zBqfP3UNfG7fBkxnstk2W+/nTrJd3ITUNSQmkLrRyWjtowlqelx1eFIRaLbzKUv4Mqc2cOACiVbr2z3BdflIyaNXKqmxHoOs2P2Be39SEO5EapJEP98kFeFu10wWzcdABUot/sh6kPpxkEHKuoaGE98X//rkW+ioFxMAT19SQ5rO3qVeUPUxo+mYmq90IrvGgSdgp9ZnhCBI/UW4lIn+MzsrKXX5RbymbzQaLHyPBbwIDAQAB';





-- GRANT USAGE ON SCHEMA gives you a keycard that lets you walk onto the floor. It does not give you a key to any room on that floor. 
GRANT USAGE ON SCHEMA data_platform_db.raw TO ROLE data_platform_role;
GRANT USAGE ON SCHEMA data_platform_db.raw TO ROLE kafka_streamer_role;
GRANT USAGE ON SCHEMA data_platform_db.silver TO ROLE data_platform_role;
GRANT USAGE ON SCHEMA data_platform_db.gold TO ROLE data_platform_role;


-- This role can only create tables on silver or gold schemas
GRANT CREATE TABLE ON SCHEMA data_platform_db.silver TO ROLE data_platform_role;
GRANT CREATE TABLE ON SCHEMA data_platform_db.gold TO ROLE data_platform_role;



-- Note: 
-- ALL = "grant access to everything that exists right now"
-- FUTURE = "grant access to everything that will be created from now on". 
-- This matters because DBT will create new tables, and without "FUTURE" grants the role won't automatically have access to CREATE, INSERT or SELECT from tables that do not exist yet
GRANT INSERT ON TABLE data_platform_db.raw.streamed_sales TO ROLE kafka_streamer_role;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA data_platform_db.raw TO ROLE data_platform_role;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA data_platform_db.silver TO ROLE data_platform_role;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA data_platform_db.gold TO ROLE data_platform_role;


GRANT SELECT, INSERT ON FUTURE TABLES IN SCHEMA data_platform_db.raw TO ROLE data_platform_role;
GRANT SELECT, INSERT ON FUTURE TABLES IN SCHEMA data_platform_db.silver TO ROLE data_platform_role;
GRANT SELECT, INSERT ON FUTURE TABLES IN SCHEMA data_platform_db.gold TO ROLE data_platform_role;




USE ROLE ACCOUNTADMIN;
USE WAREHOUSE data_platform_wh;
USE SCHEMA data_platform_db.raw;



-- Create a snowpipe for streaming
CREATE PIPE IF NOT EXISTS kafka_pipe
AS COPY INTO data_platform_db.raw.streamed_sales (raw_data, source_file)
FROM (
  SELECT $1:raw_data, $1:source_file
  FROM TABLE(DATA_SOURCE(TYPE => 'STREAMING'))
);


-- Show all pipes on this snowflake account
SHOW PIPES LIKE 'KAFKA_PIPE' IN ACCOUNT;

-- Allow kafka_streamer_role to operate pipe
GRANT OPERATE ON PIPE data_platform_db.raw.kafka_pipe TO ROLE kafka_streamer_role;