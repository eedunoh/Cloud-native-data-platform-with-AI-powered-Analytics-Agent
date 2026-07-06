{% test conditional_not_null(model, column_name, condition_column, operator, condition_value) %}

    SELECT *
    FROM {{model}}
    WHERE {{condition_column}} {{operator}} {{condition_value}}    -- condition value has to be a list
    AND {{column_name}} IS NOT NULL

{% endtest %}

-- Note: When a generic test is attached to a column, dbt automatically passes column_name to the test macro (the name of the column the test is defined under), same thing you have for "model"
-- I got an error because my macro did not have the needed variable "column_name" in my macro, so I got this error:

-- macro 'dbt_macro__test_conditional_not_null' takes no keyword argument 'column_name'

-- Initially, I had target_column in the macro then passed its values in the yaml (the value of target_column is literally the column_name), dbt was the major source of the error. 

-- To fix the issue, I removed target_column entirely from macro and yaml, then added column_name on macro ONLY

