WITH base AS (
    SELECT
        store_id,
        open_date,  
        country,
        state,
        square_meters,
    FROM {{ ref("stores") }}
),


sales_products_1 AS (
    SELECT 
        ss.store_id,
        ss.user_id,
        ss.quantity,
        pd.unit_cost_in_usd, 
        pd.unit_price_in_usd,
        (pd.unit_cost_in_usd * ss.quantity)::DECIMAL(10, 2) AS total_cost_in_usd,
        (pd.unit_price_in_usd * ss.quantity)::DECIMAL(10, 2) AS total_price_in_usd,
        (total_price_in_usd - total_cost_in_usd)::DECIMAL(10, 2) AS revenue_in_usd,
        ss.currency_code,
        er.exchange AS exchange_rate_to_dollar,
        (total_cost_in_usd * er.exchange)::DECIMAL(10,2) AS total_cost_in_local_currency,
        (total_price_in_usd * er.exchange)::DECIMAL(10,2) AS total_price_in_local_currency,
        (total_price_in_local_currency - total_cost_in_local_currency)::DECIMAL(10, 2) AS revenue_in_local_currency
    FROM {{ ref("streamed_sales") }} ss

    LEFT JOIN {{ ref("products") }} pd
    ON ss.product_id = pd.product_id

    LEFT JOIN {{ ref("exchange_rates") }} er
    ON ss.order_date::DATE = er.date::DATE
    AND ss.currency_code = er.currency
),

sales_products_2 AS (
    SELECT
        store_id,
        COUNT(DISTINCT user_id) AS total_unique_buyers,
        SUM(quantity) AS total_products_sold,
        SUM(revenue_in_local_currency) AS total_revenue_in_local_currency,
        SUM(revenue_in_usd) AS total_revenue_in_usd
    FROM sales_products_1
    GROUP BY store_id
),


top_selling_product_by_order AS (
    SELECT 
        store_id,
        product,
        total_ordered,
    FROM (
            SELECT 
                ss.store_id,
                pd.product_name AS product,
                SUM(quantity) AS total_ordered

            FROM {{ ref("streamed_sales") }} ss

            LEFT JOIN {{ ref("products") }} pd
            ON ss.product_id = pd.product_id

            GROUP BY store_id, product
    )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY store_id ORDER BY total_ordered DESC) = 1
),


product_by_revenue AS (
    SELECT 
        store_id,
        product,
        SUM(revenue) AS total_revenue
    FROM (
            SELECT 
                ss.store_id,
                pd.product_name AS product,
                pd.unit_cost_in_usd, 
                pd.unit_price_in_usd,
                pd.unit_cost_in_usd * ss.quantity AS total_cost_in_usd,
                pd.unit_price_in_usd * ss.quantity AS total_price_in_usd,
                (total_price_in_usd - total_cost_in_usd)::DECIMAL(10, 2) AS revenue
            FROM {{ ref("streamed_sales") }} ss

            LEFT JOIN {{ ref("products") }} pd
            ON ss.product_id = pd.product_id
    )
    GROUP BY store_id, product
),


top_selling_product_by_revenue AS (
    SELECT 
        store_id,
        product,
        total_revenue
    FROM product_by_revenue
    QUALIFY ROW_NUMBER() OVER (PARTITION BY store_id ORDER BY total_revenue DESC) = 1
)


SELECT
    b.store_id,
    b.open_date,  
    b.country,
    b.state,
    b.square_meters,
    sp.total_unique_buyers,
    sp.total_products_sold,
    sp.total_revenue_in_local_currency,
    sp.total_revenue_in_usd,
    tpo.product AS top_selling_product_by_order,
    tpr.product AS top_selling_product_by_revenue
FROM base b

LEFT JOIN sales_products_2 sp
ON b.store_id = sp.store_id

LEFT JOIN top_selling_product_by_order tpo
ON b.store_id = tpo.store_id

LEFT JOIN top_selling_product_by_revenue tpr
ON b.store_id = tpr.store_id

ORDER BY b.store_id ASC
