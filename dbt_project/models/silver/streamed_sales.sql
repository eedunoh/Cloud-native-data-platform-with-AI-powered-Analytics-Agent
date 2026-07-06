WITH source AS (
    SELECT
        -- convert the string to a structured object. try_parse_json is used because try_parse will throw an error if json is invalid but try_parse_json will return null without disrupting other runs
        TRY_PARSE_JSON(raw_data) AS record,
        source_file,
        ingested_at
    FROM {{ source('source', 'streamed_sales') }}
),


-- The source table already has one row per JSON object. Each line in the sample is a complete record. So no splitting into rows is needed.
-- The extraction of columns is done right inside the parsed CTE using Snowflake’s native : operator

-- This is the same as writing: try_parse_json(raw_data):"key"::<data_type> as column_name.  The process repeats for each key in the json object in all rows

-- NOTE: We can write a macro function for this using a 'for' and 'if' loop but it will be an overkill.
parsed AS (
    SELECT
        record:"Order Number"::BIGINT               AS order_id,
        record:"Order Date"::VARCHAR                AS order_date_text,
        record:"CustomerKey"::INT                   AS user_id,
        record:"Currency Code"::VARCHAR             AS currency_code,
        record:"Line Item"::INT                     AS line_item,
        record:"ProductKey"::INT                    AS product_id,
        record:"Quantity"::INT                      AS quantity,
        record:"StoreKey"::INT                      AS store_id,
        NULLIF(record:"Delivery Date"::VARCHAR, '') AS delivery_date_text,
        record:"_streamed_at"::VARCHAR              AS streamed_at_text,
        record:"_row_index"::BIGINT                 AS stream_row_index,
        source_file,
        record:"_source"::VARCHAR                   AS source_name,
        ingested_at
    FROM source
)


SELECT
    order_id,
    TRY_TO_DATE(order_date_text, 'MM/DD/YYYY')      AS order_date,                    
    user_id,
    currency_code,
    line_item,
    product_id,
    quantity,
    store_id,
    TRY_TO_DATE(delivery_date_text, 'MM/DD/YYYY')   AS delivery_date,                
    TRY_TO_TIMESTAMP(streamed_at_text, 'YYYY-MM-DD"T"HH24:MI:SS.FF6') AS streamed_at,
    stream_row_index,
    source_file,
    source_name,
    ingested_at
FROM parsed
QUALIFY ROW_NUMBER() OVER (PARTITION BY order_id, user_id, product_id, order_date, line_item ORDER BY streamed_at DESC, ingested_at DESC) = 1  -- Remove duplicate and select the most recent entry of a particular order.
ORDER BY stream_row_index ASC
