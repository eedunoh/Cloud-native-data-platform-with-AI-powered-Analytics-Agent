{% test outlier_detection(model, column_name, iqr_factor=1.5) %}
    WITH quartiles AS (
        SELECT 
            percentile_cont(0.25) WITHIN GROUP (ORDER BY {{column_name}}) AS q1,
            percentile_cont(0.75) WITHIN GROUP (ORDER BY {{column_name}}) AS q3
        FROM {{model}}
        WHERE {{column_name}} IS NOT NULL
    ),

    bounds AS (
        SELECT 
            q1,
            q3,
            q1 - (q3 - q1) * {{iqr_factor}} AS lower_bound,
            q3 + (q3 - q1) * {{iqr_factor}} AS upper_bound
        FROM quartiles
    )

    SELECT *
    FROM {{model}}, bounds
    WHERE {{column_name}} IS NULL   -- checks if the column has null values
    OR {{column_name}} < lower_bound  -- checks lower outliers
    OR {{column_name}} > upper_bound      -- checks higher outliers

{% endtest %}