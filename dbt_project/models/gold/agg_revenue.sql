WITH base AS (
    SELECT 
        DATE_TRUNC(day, order_date) AS period,
        ss.order_id,
        ss.order_date,                    
        ss.user_id,
        ss.currency_code,
        ss.line_item,
        ss.product_id,
        ss.quantity,
        ss.store_id,
        ss.delivery_date,
        pd.unit_cost_in_usd, 
        pd.unit_price_in_usd,
        pd.unit_cost_in_usd * ss.quantity AS total_cost_in_usd,
        pd.unit_price_in_usd * ss.quantity AS total_price_in_usd,
        (total_price_in_usd - total_cost_in_usd)::DECIMAL(10, 2) AS revenue_in_usd,
        DENSE_RANK() OVER(PARTITION BY user_id ORDER BY order_date ASC, order_id ASC) AS order_rank_per_user,
        CASE WHEN order_rank_per_user = 1 THEN 'first_time_buyer' ELSE 'returning_buyer' END AS customer_type,
        CASE WHEN order_rank_per_user = 1 THEN True ELSE False END AS is_first_time_buyer
    FROM {{ ref("streamed_sales") }} ss

    LEFT JOIN {{ ref("products") }} pd
    ON ss.product_id = pd.product_id
),


agg_stats AS (
    SELECT 
        period,
        COUNT(DISTINCT user_id) AS total_active_users,
        COUNT(DISTINCT CASE WHEN is_first_time_buyer = true THEN user_id END) AS total_new_buyers,
        COUNT(DISTINCT CASE WHEN is_first_time_buyer = false THEN user_id END) AS total_returning_buyers,
        SUM(quantity) AS total_products_sold,
        SUM(revenue_in_usd) AS total_revenue_in_usd,
    FROM base
    GROUP BY period
),


country_by_revenue AS (
    SELECT 
        period,
        country,
        SUM(revenue_in_usd) AS total_revenue_in_usd
    FROM (
            SELECT 
                DATE_TRUNC(day, order_date) AS period,
                st.country,
                pd.unit_cost_in_usd, 
                pd.unit_price_in_usd,
                pd.unit_cost_in_usd * ss.quantity AS total_cost_in_usd,
                pd.unit_price_in_usd * ss.quantity AS total_price_in_usd,
                (total_price_in_usd - total_cost_in_usd)::DECIMAL(10, 2) AS revenue_in_usd
            FROM {{ ref("streamed_sales") }} ss

            LEFT JOIN {{ ref("stores") }} st
            ON ss.store_id = st.store_id

            LEFT JOIN {{ ref("products") }} pd
            ON ss.product_id = pd.product_id
    )
    GROUP BY period, country
),


top_country_by_revenue AS (
    SELECT 
        period,
        country,
        total_revenue_in_usd,
    FROM country_by_revenue
    QUALIFY ROW_NUMBER() OVER (PARTITION BY period ORDER BY total_revenue_in_usd DESC) = 1
),


top_selling_product_by_order AS (
    SELECT 
        period,
        product,
        total_ordered,
    FROM (
            SELECT 
                DATE_TRUNC(day, order_date) AS period,
                pd.product_name AS product,
                SUM(quantity) AS total_ordered

            FROM {{ ref("streamed_sales") }} ss

            LEFT JOIN {{ ref("products") }} pd
            ON ss.product_id = pd.product_id

            GROUP BY period, product
    )
QUALIFY ROW_NUMBER() OVER (PARTITION BY period ORDER BY total_ordered DESC) = 1
),


product_by_revenue AS (
    SELECT 
        period,
        product,
        SUM(revenue_in_usd) AS total_revenue_in_usd
    FROM (
            SELECT 
                DATE_TRUNC(day, order_date) AS period,
                pd.product_name AS product,
                pd.unit_cost_in_usd, 
                pd.unit_price_in_usd,
                pd.unit_cost_in_usd * ss.quantity AS total_cost_in_usd,
                pd.unit_price_in_usd * ss.quantity AS total_price_in_usd,
                (total_price_in_usd - total_cost_in_usd)::DECIMAL(10, 2) AS revenue_in_usd
            FROM {{ ref("streamed_sales") }} ss

            LEFT JOIN {{ ref("products") }} pd
            ON ss.product_id = pd.product_id
    )
    GROUP BY period, product
),


top_selling_product_by_revenue AS (
    SELECT 
        period,
        product,
        total_revenue_in_usd
    FROM product_by_revenue
    QUALIFY ROW_NUMBER() OVER (PARTITION BY period ORDER BY total_revenue_in_usd DESC) = 1
),

final AS (
    SELECT
        ags.period,
        ags.total_active_users,
        ags.total_new_buyers,
        ags.total_returning_buyers,
        ags.total_products_sold,
        ags.total_revenue_in_usd,
        lag(ags.total_revenue_in_usd, 1) OVER(ORDER BY ags.period ASC) AS last_revenue_in_usd,
        tc.country AS top_country_by_revenue,
        tpo.product AS top_selling_product_by_order,
        tpr.product AS top_selling_product_by_revenue
    FROM agg_stats ags

    LEFT JOIN top_country_by_revenue tc
    ON ags.period = tc.period

    LEFT JOIN top_selling_product_by_order tpo
    ON ags.period = tpo.period

    LEFT JOIN top_selling_product_by_revenue tpr
    ON ags.period = tpr.period

    ORDER BY ags.period ASC
)


SELECT
    period,
    total_active_users,
    total_new_buyers,
    total_returning_buyers,
    total_products_sold,
    total_revenue_in_usd,
    ((total_revenue_in_usd - last_revenue_in_usd)/last_revenue_in_usd)::DECIMAL(10,3) AS pct_change_in_daily_revenue,
    SUM(total_revenue_in_usd) OVER (ORDER BY period ASC ROWS BETWEEN 6 PRECEDING AND CURRENT ROW ) AS cumulative_revenue_last_7_days,
    top_country_by_revenue,
    top_selling_product_by_order,
    top_selling_product_by_revenue
FROM final
ORDER BY period ASC