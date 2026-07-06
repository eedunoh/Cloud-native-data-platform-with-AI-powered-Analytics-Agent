WITH source AS (
    SELECT
        -- convert the string to a structured object. try_parse_json is used because try_parse will throw an error if json is invalid but try_parse_json will return null without disrupting other runs
        TRY_PARSE_JSON(raw_data) AS record,
        source_file,
        ingested_at
    FROM {{ source('source', 'customers') }}
),


parsed AS (
    SELECT
        record:"CustomerKey"::VARCHAR       AS user_id_text,
        record:"Name"::VARCHAR              AS user_name,
        record:"Gender"::VARCHAR            AS gender,
        record:"Birthday"::VARCHAR          AS date_of_birth_text,
        record:"Continent"::VARCHAR         AS continent,
        record:"Country"::VARCHAR           AS country,
        record:"State"::VARCHAR             AS state,
        record:"State Code"::VARCHAR        AS state_code,
        record:"City"::VARCHAR              AS city,
        record:"Zip Code"::VARCHAR          AS zip_code,
        record:"Updated at"::VARCHAR        AS updated_at_text,
        source_file,
        ingested_at
    FROM source
)


SELECT 
    TRY_TO_NUMBER(user_id_text)::BIGINT AS user_id,   
    user_name,
    gender,
    TRY_TO_DATE(date_of_birth_text, 'MM/DD/YYYY') AS date_of_birth, 
    continent,
    country,
    state,
    state_code,
    city,
    zip_code,
    TRY_TO_TIMESTAMP(updated_at_text, 'MM/DD/YYYY HH24:MI:SS') AS updated_at,   
    source_file,
    ingested_at
FROM parsed
QUALIFY ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY updated_at DESC, ingested_at DESC) = 1          -- Remove duplicate and select the most recent entry of a particular user record
ORDER BY user_id ASC
