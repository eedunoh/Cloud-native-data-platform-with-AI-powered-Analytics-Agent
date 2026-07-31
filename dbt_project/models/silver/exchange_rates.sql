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
        record:"date"::VARCHAR        AS date_text,
        record:"currency"::VARCHAR    AS currency,
        record:"exchange"::VARCHAR    AS exchange_text,
        record:"updated_at"::VARCHAR  AS updated_at_text,
        source_file,
        ingested_at
    FROM source
)

SELECT
    TRY_TO_DATE(date_text, 'MM/DD/YYYY') AS date,                               
    currency,
    CAST(REPLACE(exchange_text, '"', '') AS FLOAT) AS exchange,
    TRY_TO_TIMESTAMP(updated_at_text, 'YYYY-MM-DD HH24:MI:SS') AS updated_at,   
    source_file,
    ingested_at
FROM parsed
QUALIFY ROW_NUMBER() OVER (PARTITION BY date, currency ORDER BY updated_at DESC, ingested_at DESC) = 1   -- Remove duplicates if they exist
ORDER BY date ASC, currency ASC

