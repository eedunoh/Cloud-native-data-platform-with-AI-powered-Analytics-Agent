WITH source AS (
    SELECT
        -- convert the string to a structured object. try_parse_json is used because try_parse will throw an error if json is invalid but try_parse_json will return null without disrupting other runs
        TRY_PARSE_JSON(raw_data) AS record,
        source_file,
        ingested_at
    FROM {{ source('source', 'data_dictionary') }}
),

parsed AS (
    SELECT
        record:"table"::VARCHAR         AS table_name,
        record:"field"::VARCHAR         AS field,
        record:"description"::VARCHAR   AS description,
        record:"updated_at"::VARCHAR    AS updated_at_text,
        source_file,
        ingested_at
    FROM source
)

SELECT
    CASE WHEN table_name = 'Sales' THEN 'Streamed_Sales' ELSE table_name END AS table_names,
    field,
    description,
    TRY_TO_TIMESTAMP(updated_at_text, 'YYYY-MM-DD HH24:MI:SS') AS updated_at,   
    source_file,
    ingested_at
FROM parsed
QUALIFY ROW_NUMBER() OVER (PARTITION BY table_name, field  ORDER BY updated_at DESC, ingested_at DESC) = 1   -- Remove duplicates if they exist
ORDER BY table_name
