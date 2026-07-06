WITH source AS (
    SELECT
        -- convert the string to a structured object. try_parse_json is used because try_parse will throw an error if json is invalid but try_parse_json will return null without disrupting other runs
        TRY_PARSE_JSON(raw_data) AS record,
        source_file,
        ingested_at
    FROM {{ source('source', 'exchange_rates') }}
),

parsed AS (
    SELECT
        record:"Date"::VARCHAR        AS date_text,
        record:"Currency"::VARCHAR    AS currency,
        record:"Exchange"::VARCHAR    AS exchange_text,
        source_file,
        ingested_at
    FROM source
)

SELECT
    TRY_TO_DATE(date_text, 'MM/DD/YYYY') AS date,                               
    currency,
    CAST(REPLACE(exchange_text, '"', '') AS FLOAT) AS exchange, 
    source_file,
    ingested_at
FROM parsed
QUALIFY ROW_NUMBER() OVER (PARTITION BY date, currency ORDER BY exchange DESC) = 1   -- Remove duplicates if they exist
ORDER BY date ASC, currency ASC

