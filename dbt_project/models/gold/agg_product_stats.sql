WITH base AS (
    SELECT 
        product_id,  
        sub_category,
        brand,                                       
        product_name,
        unit_cost_in_usd,       
        unit_price_in_usd
    FROM {{ ref("products") }}
),


sales_products_1 AS (
    SELECT 
        ss.user_id,
        ss.quantity,
        pd.product_id,  
        pd.sub_category,
        pd.brand,                                       
        pd.product_name,
        pd.unit_cost_in_usd,
        pd.unit_price_in_usd,
        (pd.unit_cost_in_usd * ss.quantity)::DECIMAL(10, 2) AS total_cost_in_usd,
        (pd.unit_price_in_usd * ss.quantity)::DECIMAL(10, 2) AS total_price_in_usd,
        (total_price_in_usd - total_cost_in_usd)::DECIMAL(10, 2) AS revenue_in_usd

    FROM {{ ref("streamed_sales") }} ss

    LEFT JOIN {{ ref("products") }} pd
    ON ss.product_id = pd.product_id
),


sales_products_2 AS (
    SELECT
        product_id,  
        sub_category,
        brand,                                       
        product_name,
        COUNT(DISTINCT user_id) AS total_unique_buyers,
        SUM(quantity) AS total_sold,
        SUM(total_cost_in_usd) AS total_cost_in_usd,
        SUM(total_price_in_usd) AS total_price_in_usd,
        SUM(revenue_in_usd) AS total_revenue_in_usd
    FROM sales_products_1
    GROUP BY product_id, sub_category, brand, product_name
),


top_purchase_country AS (
    SELECT 
        product_id,  
        sub_category,
        brand,                                       
        product_name,
        country AS top_purchase_country,
        total_sold
    FROM (
            SELECT
                pd.product_id,  
                pd.sub_category,
                pd.brand,                                       
                pd.product_name,
                st.country,
                SUM(ss.quantity) AS total_sold
            FROM {{ ref("streamed_sales") }} ss

            LEFT JOIN {{ ref("products") }} pd
            ON ss.product_id = pd.product_id

            LEFT JOIN {{ ref("stores") }} st
            ON ss.store_id = st.store_id

            GROUP BY pd.product_id, pd.sub_category, pd.brand, pd.product_name, st.country
            ORDER BY pd.product_id ASC
        )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id, sub_category, brand, product_name ORDER BY total_sold DESC) = 1
)


SELECT 
    b.product_id,
    b.sub_category,
    b.brand,                                       
    b.product_name,
    b.unit_cost_in_usd,       
    b.unit_price_in_usd,
    total_unique_buyers,
    total_sold,
    total_cost_in_usd,
    total_price_in_usd,
    total_revenue_in_usd,
    tpc.top_purchase_country
FROM base b
LEFT JOIN sales_products_2 sp
USING (product_id, sub_category, brand, product_name)

LEFT JOIN top_purchase_country tpc
USING (product_id, sub_category, brand, product_name)



-- WHAT TO DO WHEN UNIT COST AND UNIT PRICE CHANGES: 
-- The new product variant is tagged with a new product_id + other details. That is, it is registered as an entirely new products with its costs and prices.
-- This is similar to loan products where different loan products could have the same principal but different interests, tenures etc.
-- Creating a new product_id for the product + new costs sounds good, while the old remains active for old records. 
-- More like product SKU