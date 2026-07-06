WITH base AS (
    SELECT
        ss.user_id,
        ss.order_id,
        ss.order_date,                    
        DENSE_RANK() OVER(PARTITION BY ss.user_id ORDER BY ss.order_date ASC, ss.order_id ASC) AS order_rank_per_user,
        CASE WHEN order_rank_per_user = 1 THEN 'first_time_buyer' ELSE 'returning_buyer' END AS customer_type,
        ss.line_item,
        ss.product_id,
        pd.product_name,
        ss.quantity,
        ss.store_id,
        st.country AS store_location,
        CASE WHEN ss.store_id = 0 THEN 'False' ELSE 'True: In-Store Pickup' END AS is_walk_in_purchase,
        ss.delivery_date,
        pd.unit_cost_in_usd, 
        pd.unit_price_in_usd,
        (pd.unit_cost_in_usd * ss.quantity)::DECIMAL(10,2) AS total_cost_in_usd,
        (pd.unit_price_in_usd * ss.quantity)::DECIMAL(10,2) AS total_price_in_usd,
        (total_price_in_usd - total_cost_in_usd)::DECIMAL(10, 2) AS revenue_in_usd,
        ss.currency_code,
        er.exchange AS exchange_rate_to_dollar,
        (total_price_in_usd * er.exchange)::DECIMAL(10,2) AS total_price_in_local_currency
    FROM {{ ref("streamed_sales") }} ss

    LEFT JOIN {{ ref("products") }} pd
    ON ss.product_id = pd.product_id

    LEFT JOIN {{ ref("stores") }} st
    ON ss.store_id = st.store_id

    LEFT JOIN {{ ref("exchange_rates") }} er
    ON ss.order_date::DATE = er.date::DATE
    AND ss.currency_code = er.currency
)

SELECT
    user_id,
    order_id,
    order_date,                    
    customer_type,
    line_item,
    product_id,
    product_name,
    quantity,
    store_id,
    store_location,
    is_walk_in_purchase,
    delivery_date,
    unit_cost_in_usd, 
    unit_price_in_usd,
    total_cost_in_usd,
    total_price_in_usd,
    revenue_in_usd,
    currency_code,
    exchange_rate_to_dollar,
    total_price_in_local_currency
FROM base b