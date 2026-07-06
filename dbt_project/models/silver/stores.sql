
WITH source AS (
    SELECT
        -- convert the string to a structured object. try_parse_json is used because try_parse will throw an error if json is invalid but try_parse_json will return null without disrupting other runs
        TRY_PARSE_JSON(raw_data) AS record,
        source_file,
        ingested_at
    FROM {{ source('source', 'stores') }}
),

parsed AS (
    SELECT
        record:"StoreKey"::INT          AS store_id,
        record:"Open Date"::VARCHAR     AS open_date_text,
        record:"Country"::VARCHAR       AS country,
        record:"State"::VARCHAR         AS state,
        record:"Square Meters"::VARCHAR AS square_meters_text,
        record:"Updated at"::VARCHAR    AS updated_at_text,
        source_file,
        ingested_at
    FROM source
)

SELECT 
    store_id,
    TRY_TO_DATE(open_date_text, 'MM/DD/YYYY') AS open_date,  
    country,
    state,
    TRY_TO_NUMBER(REPLACE(square_meters_text, '"', ''))::INT AS square_meters, 
    TRY_TO_TIMESTAMP(updated_at_text, 'MM/DD/YYYY HH24:MI:SS') AS updated_at,  
    source_file,
    ingested_at
FROM parsed
QUALIFY ROW_NUMBER() OVER (PARTITION BY store_id ORDER BY updated_at DESC, ingested_at DESC) = 1     -- Remove duplicate and select the most recent entry of a particular product/brand
ORDER BY store_id ASC
