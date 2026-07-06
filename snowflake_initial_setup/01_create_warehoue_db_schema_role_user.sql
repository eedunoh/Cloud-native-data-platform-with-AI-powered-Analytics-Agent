-- THIS SQL FILE WILL BE EXECUTED MANUALLY

USE ROLE ACCOUNTADMIN;

-- Creae the warehouse
-- Since this is a development stage, I will de-activate some parameters listed below;
-- AUTO_SUSPEND = 60 means shut down after 60 seconds of inactivity
-- AUTO_RESUME = TRUE means start automatically when a query runs
-- These saves credits

CREATE WAREHOUSE IF NOT EXISTS data_platform_wh
    WAREHOUSE_SIZE = 'X-SMALL';
    -- AUTO_SUSPEND = 60
    -- AUTO_RESUME = TRUE


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


-- Create a dedicated role to be used by dbt
-- Best practice — never use ACCOUNTADMIN for day to day operations
CREATE ROLE IF NOT EXISTS data_platform_role;


-- GRANT PERMISSIONS TO THE data_plat_form_role

-- This role can use this warehouse
GRANT USAGE ON WAREHOUSE data_platform_wh TO ROLE data_platform_role;

-- This role can use this database
GRANT USAGE ON DATABASE data_platform_db TO ROLE data_platform_role;

-- This role can use any of the schemas but further permissions are required. 
-- GRANT USAGE ON SCHEMA gives you a keycard that lets you walk onto the floor. It does not give you a key to any room on that floor. 
GRANT USAGE ON SCHEMA data_platform_db.raw TO ROLE data_platform_role;
GRANT USAGE ON SCHEMA data_platform_db.silver TO ROLE data_platform_role;
GRANT USAGE ON SCHEMA data_platform_db.gold TO ROLE data_platform_role;


-- This role can only create tables on silver or gold schemas
GRANT CREATE TABLE ON SCHEMA data_platform_db.silver TO ROLE data_platform_role;
GRANT CREATE TABLE ON SCHEMA data_platform_db.gold TO ROLE data_platform_role;


-- Note: 
-- ALL = "grant access to everything that exists right now"
-- FUTURE = "grant access to everything that will be created from now on". 
-- This matters because dbt will create new tables, and without "FUTURE" grants the role won't automatically have access to tables that don't exist yet

GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA data_platform_db.silver TO ROLE data_platform_role;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA data_platform_db.gold TO ROLE data_platform_role;

-- This role ONLY select (read) from tables in the raw schema it can't insert (or write into them).
-- On the silver and gold schema, this role can select and insert into any table created previously or yet to be created.
GRANT SELECT ON FUTURE TABLES IN SCHEMA data_platform_db.raw TO ROLE data_platform_role;
GRANT SELECT, INSERT ON FUTURE TABLES IN SCHEMA data_platform_db.silver TO ROLE data_platform_role;
GRANT SELECT, INSERT ON FUTURE TABLES IN SCHEMA data_platform_db.gold TO ROLE data_platform_role;


-- Create a dedicated user
CREATE USER IF NOT EXISTS data_platform_user
    PASSWORD = 'dataBaseUser6654!&'
    DEFAULT_ROLE = data_platform_role
    DEFAULT_WAREHOUSE = data_platform_wh
    DEFAULT_NAMESPACE = data_platform_db.raw;


-- Grant role to the user OR allow user assume the role
GRANT ROLE data_platform_role TO USER data_platform_user;


-- Also grant dataplatform role to ACCOUNTADMIN. 
-- Without this permission, ACCOUNTADMIN will not be able to carry out any action on tables created by dataplatform role despite ACCOUNTADMIN role being a higher lever role.
-- So this command literally grants ACCOUNTADMIN all permissions givent to data_platform role.
GRANT ROLE data_platform_role TO ROLE ACCOUNTADMIN;