{% test is_valid_date_format(model, column_name, date_format) %}

    SELECT *
    FROM {{model}}
    WHERE try_to_date({{column_name}}, {{date_format}}) IS NULL

{% endtest %}