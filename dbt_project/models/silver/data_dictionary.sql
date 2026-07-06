with source as (
    select
        -- convert the string to a structured object. try_parse_json is used because try_parse will throw an error if json is invalid but try_parse_json will return null without disrupting other runs
        try_parse_json(raw_data) as record,
        source_file,
        ingested_at
    from {{ source('source', 'data_dictionary') }}
),

parsed as (
    select
        record:"Table"::varchar         as table_name,
        record:"Field"::varchar         as field,
        record:"Description"::varchar   as description,
        source_file,
        ingested_at
    from source
)

select
    Case When table_name = 'Sales' Then 'Streamed_Sales' Else table_name End As table_names,
    field,
    description,
    source_file,
    ingested_at
from parsed
Order by table_name
