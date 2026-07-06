WITH base AS (
    SELECT 
        user_id,   
        user_name,
        gender,
        date_of_birth, 
        continent,
        country,
        state,
        city,
    FROM {{ ref("customers") }}
),

product_info AS (
    SELECT                    
        ss.user_id,
        SUM(quantity) AS total_products_ordered,
        SUM(pd.unit_price_in_usd * ss.quantity)::DECIMAL(10, 2) AS total_order_value,
        (total_order_value/total_products_ordered)::DECIMAL(10, 2) AS average_order_price,
        SUM((pd.unit_price_in_usd * ss.quantity) - (pd.unit_cost_in_usd * ss.quantity))::DECIMAL(10, 2) AS net_revenue_on_user,
        MIN(ss.order_date) AS first_purchase_date,
        MAX(ss.order_date) AS most_recent_purchase_date,
        getdate()::DATE - most_recent_purchase_date::DATE AS days_since_last_purchase
    FROM {{ ref("streamed_sales") }} ss

    LEFT JOIN {{ ref("products") }} pd
    ON ss.product_id = pd.product_id

    GROUP BY ss.user_id
),


product_dict AS (
    SELECT
        user_id,
        OBJECT_AGG(product_name, count::variant) AS unique_product_count
    FROM (
            SELECT                    
                ss.user_id,
                pd.product_name,
                SUM(quantity) AS count
            FROM {{ ref("streamed_sales") }} ss

            LEFT JOIN {{ ref("products") }} pd
            ON ss.product_id = pd.product_id

            GROUP BY ss.user_id, pd.product_name
        )
    GROUP BY user_id
),

profile_mod_count AS (
    SELECT 
        user_id,
        COUNT(*) AS profile_modification_count
    FROM {{ ref("core_customers") }}
    GROUP BY user_id
)


SELECT 
    b.user_id, 
    -- we subtract 1 from the actual count because every initial record will have a 1 count. Subsequent changes will start from 2. So its best we remove the initial record entry
    pm.profile_modification_count - 1 AS profile_modification_count,
    b.user_name,
    b.gender,
    b.date_of_birth, 
    b.continent,
    b.country,
    b.state,
    b.city,
    pd.unique_product_count,
    pi.total_products_ordered,
    pi.total_order_value,
    pi.average_order_price,
    pi.net_revenue_on_user,
    pi.first_purchase_date,
    pi.most_recent_purchase_date,
    pi.days_since_last_purchase
FROM base b

LEFT JOIN product_info pi
ON b.user_id = pi.user_id

LEFT JOIN product_dict pd
ON b.user_id = pd.user_id

LEFT JOIN profile_mod_count pm
ON b.user_id = pm.user_id
