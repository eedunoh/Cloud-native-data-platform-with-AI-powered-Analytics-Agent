WITH source AS (
    SELECT
        -- convert the string to a structured object. try_parse_json is used because try_parse will throw an error if json is invalid but try_parse_json will return null without disrupting other runs
        TRY_PARSE_JSON(raw_data) AS record,
        source_file,
        ingested_at
    FROM {{ source('source', 'ai_document_extracts') }}
),

parsed AS (
    SELECT
        record:"policy_name"::VARCHAR               AS policy_name,
        record:"effective_date"::VARCHAR            AS effective_date_text,
        record:"summary"::VARCHAR                   AS summary,
        record:"key_rules"::VARCHAR                 AS key_rules,
        record:"compliance_requirements"::VARCHAR   AS compliance_requirements,
        source_file,
        ingested_at
    FROM source
)


SELECT
    policy_name,
    TRY_TO_DATE(effective_date_text, 'MM/DD/YYYY') AS effective_date,
    summary,
    key_rules,
    compliance_requirements,
    source_file,
    ingested_at
FROM parsed
QUALIFY ROW_NUMBER() OVER (PARTITION BY policy_name ORDER BY effective_date_text DESC, ingested_at DESC) = 1     -- Remove duplicate and select the most recent entry of a particular policy
ORDER BY effective_date ASC
