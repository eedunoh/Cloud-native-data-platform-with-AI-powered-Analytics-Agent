WITH source AS (
    SELECT
        -- convert the string to a structured object. try_parse_json is used because try_parse will throw an error if json is invalid but try_parse_json will return null without disrupting other runs
        TRY_PARSE_JSON(raw_data) AS record,
        source_file,
        ingested_at
    FROM {{ source('source', 'products') }}
),

parsed AS (
    SELECT
        record:"ProductKey"::VARCHAR        AS product_id_text,
        record:"Product Name"::VARCHAR      AS product_name,
        record:"Brand"::VARCHAR             AS brand,
        record:"Color"::VARCHAR             AS colour,
        record:"CategoryKey"::VARCHAR       AS category_id_text,
        record:"Category"::VARCHAR          AS category,
        record:"SubcategoryKey"::VARCHAR    AS sub_category_id_text,
        record:"Subcategory"::VARCHAR       AS sub_category,
        record:"Unit Cost USD"::VARCHAR     AS unit_cost_in_usd_text,
        record:"Unit Price USD"::VARCHAR    AS unit_price_in_usd_text,
        record:"Updated at"::VARCHAR        AS updated_at_text,
        source_file,
        ingested_at
    FROM source
)


SELECT 
    TRY_TO_NUMBER(REPLACE(product_id_text, '"', ''))::INT AS product_id,                                                  
    product_name,
    brand,
    colour,
    TRY_TO_NUMBER(REPLACE(category_id_text, '"', ''))::INT AS category_id,                                               
    category,
    TRY_TO_NUMBER(REPLACE(sub_category_id_text, '"', ''))::INT AS sub_category_id,                                        
    sub_category,
    CAST(REPLACE(REPLACE(REPLACE(unit_cost_in_usd_text, '"', ''), '$', ''), ',', '') AS FLOAT) AS unit_cost_in_usd,       
    CAST(REPLACE(REPLACE(REPLACE(unit_price_in_usd_text, '"', ''), '$', ''), ',', '') AS FLOAT) AS unit_price_in_usd,
    TRY_TO_TIMESTAMP(updated_at_text, 'MM/DD/YYYY HH24:MI:SS') AS updated_at,
    source_file,
    ingested_at
FROM parsed
QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY updated_at DESC, ingested_at DESC) = 1       -- Remove duplicate and select the most recent entry of a particular product/brand
ORDER BY product_id ASC
