
PREFERRED_AI_MODEL = "openai/gpt-5.6-sol"

# PREFERRED_AI_MODEL = "anthropic/claude-sonnet-5"

# PREFERRED_AI_MODEL = "deepseek/deepseek-v4-pro-0813"


DATA_MODEL = """

DATABASE: data_platform_db

RAW SCHEMA (use only for data quality checks; row counts, freshness), do not query VARIANT content directly):
  All tables: raw_data VARIANT, source_file STRING, ingested_at TIMESTAMP_NTZ

  Tables:

    raw.streamed_sales: (Kafka streamed orders - freshness SLA: error >6h, warn >1h)
      raw_data VARIANT       - Kafka streamed raw orders data stored as JSON; see silver.data_dictionary for content
      source_file STRING     - source API/file that produced the raw data stream
      ingested_at TIMESTAMP_NTZ - when the data was loaded into Snowflake

    raw.exchange_rates
      raw_data VARIANT       - batch processed raw exchange rates; see silver.data_dictionary
      source_file STRING     - S3 bucket source
      ingested_at TIMESTAMP_NTZ

    raw.data_dictionary
      raw_data VARIANT       - raw data dictionary; see silver.data_dictionary
      source_file STRING     - S3 bucket source
      ingested_at TIMESTAMP_NTZ

    raw.products
      raw_data VARIANT       - batch processed raw products; see silver.data_dictionary
      source_file STRING     - S3 bucket source
      ingested_at TIMESTAMP_NTZ

    raw.customers
      raw_data VARIANT       - batch processed raw customers; see silver.data_dictionary
      source_file STRING     - S3 bucket source
      ingested_at TIMESTAMP_NTZ

    raw.stores
      raw_data VARIANT       - batch processed raw stores; see silver.data_dictionary
      source_file STRING     - S3 bucket source
      ingested_at TIMESTAMP_NTZ

    raw.ai_document_extracts
      raw_data VARIANT       - batch processed raw AI-extracted PDF data; see silver.data_dictionary
      source_file STRING     - S3 bucket source
      ingested_at TIMESTAMP_NTZ

      

SILVER SCHEMA (cleaned typed data. Use for your detailed analysis):
  Tables:

    silver.streamed_sales - real-time order line items (Kafka → silver)
        order_id         NUMBER(38,0) NOT NULL  - unique order identifier
        line_item        NUMBER(38,0)           - sequential item number within an order
        order_date       DATE                   - order placement date, always ≤ CURRENT_DATE
        delivery_date    DATE                   - scheduled/actual delivery date; null for physical walk-in purchases
        user_id          NUMBER(38,0)           - FK to customers (the customer who placed the order)
        store_id         NUMBER(38,0)           - FK to stores; 0 = online
        product_id       NUMBER(38,0)           - FK to products (product variation/SKU)
        quantity         NUMBER(38,0)           - number of units ordered; outliers (IQR 1.5) flagged
        currency_code    VARCHAR                - ISO currency code: AUD, CAD, EUR, GBP, USD (warn if other)
        streamed_at      TIMESTAMP_NTZ          - when the data was processed and moved by the Kafka consumer
        stream_row_index NUMBER(38,0)           - sequential index of the row within the data stream
        source_file      VARCHAR                - source API/file that produced the data stream
        source_name      VARCHAR                - Kafka topic name
        ingested_at      TIMESTAMP_NTZ          - when data was loaded into Snowflake

    silver.customers - master customer profile
        user_id         NUMBER(38,0) NOT NULL UNIQUE - unique customer identifier
        user_name       VARCHAR                  - full legal name or display name
        gender          VARCHAR                  - gender
        date_of_birth   DATE                     - date of birth
        continent       VARCHAR                  - continent of residence
        country         VARCHAR                  - country of residence; allowed values: Online, Australia, Canada, France, Germany, Italy, Netherlands, UK, US (warn if other)
        state           VARCHAR                  - full state/province name
        state_code      VARCHAR                  - standardized state/province abbreviation
        city            VARCHAR                  - city
        zip_code        VARCHAR                  - postal/zip code
        updated_at      TIMESTAMP_NTZ            - when the customer record was last modified
        source_file     VARCHAR                  - S3 bucket source (batch process)
        ingested_at     TIMESTAMP_NTZ            - when data was loaded into Snowflake

    silver.products - product master (SKU level)
        product_id          NUMBER(38,0) NOT NULL UNIQUE - unique product variation/SKU
        product_name        VARCHAR                  - descriptive product name (e.g., 'Contoso 2G MP3 Player E200 Red')
        brand               VARCHAR                  - brand/manufacturer name
        colour              VARCHAR                  - product colour
        category_id         NUMBER(38,0)             - category identifier
        category            VARCHAR                  - high-level category name (e.g., 'Audio', 'TV and Video')
        sub_category_id     NUMBER(38,0)             - subcategory identifier
        sub_category        VARCHAR                  - specific subcategory (e.g., 'MP4 & MP3', 'Televisions')
        unit_cost_in_usd    FLOAT                    - production cost per unit in USD
        unit_price_in_usd   FLOAT                    - standard list price / retail price per unit in USD
        updated_at          TIMESTAMP_NTZ            - when the product record was last modified
        source_file         VARCHAR                  - S3 bucket source (batch process)
        ingested_at         TIMESTAMP_NTZ            - when data was loaded into Snowflake

    silver.stores - store location master
        store_id        NUMBER(38,0) NOT NULL UNIQUE - unique store location identifier
        open_date       DATE                     - date the store officially opened for business
        country         VARCHAR                  - country of location; same allowed list as customers
        state           VARCHAR                  - state or province of the store
        square_meters   NUMBER(38,0)             - total physical footprint in square meters
        updated_at      TIMESTAMP_NTZ            - when the store record was last modified
        source_file     VARCHAR                  - S3 bucket source (batch process)
        ingested_at     TIMESTAMP_NTZ            - when data was loaded into Snowflake

    silver.exchange_rates - daily FX rates (vs USD)
        date        DATE                     - effective date of the exchange rate
        currency    VARCHAR                  - foreign currency code; allowed: AUD, CAD, EUR, GBP, USD (warn if other)
        exchange    FLOAT                    - exchange rate of the currency on that day (vs 1 USD)
        updated_at  TIMESTAMP_NTZ            - when the raw exchange rate record was last modified
        source_file VARCHAR                  - S3 bucket source (batch process)
        ingested_at TIMESTAMP_NTZ            - when data was loaded into Snowflake

    silver.ai_document_extracts - AI-extracted policy documents
        policy_name             VARCHAR      - official name of the internal corporate policy
        effective_date          VARCHAR      - date the policy becomes active and enforceable
        summary                 VARCHAR      - concise overview of core purpose and key points
        key_rules               VARCHAR      - primary regulations, mandates, and operational guidelines
        compliance_requirements VARCHAR      - specific actions/procedures/standards to adhere to the policy
        source_file             VARCHAR      - S3 bucket source (batch process)
        ingested_at             TIMESTAMP_NTZ - when data was loaded into Snowflake

    silver.data_dictionary - raw layer column mapping (used for schema drift detection)
        source_file   VARCHAR      - name of the raw data table
        field         VARCHAR      - original column name in the raw table (may differ from silver)
        description   VARCHAR      - detailed explanation of the column's purpose/contents in the raw table
        updated_at    TIMESTAMP_NTZ - when the raw data dictionary record was last modified
        source_file   VARCHAR      - S3 bucket source (batch process)
        ingested_at   TIMESTAMP_NTZ - when data was loaded into Snowflake

    
  Type-2 SCD snapshots (historical change tracking)

    silver.core_customers (SCD2 snapshot of customers - track historical changes)
        user_id, user_name, gender, date_of_birth, continent, country, state, state_code, city, zip_code,
        updated_at       TIMESTAMP_NTZ - when the record was last modified in the raw layer
        source_file      VARCHAR       - S3 bucket source (batch process)
        ingested_at      TIMESTAMP_NTZ - when data was loaded into Snowflake
        dbt_scd_id       VARCHAR       - unique MD5 hash identifying this row version (unique_key + monitored columns)
        dbt_updated_at   TIMESTAMP_NTZ - timestamp of the dbt snapshot run that created/verified this row
        dbt_valid_from   TIMESTAMP_NTZ - when this row version became active
        dbt_valid_to     TIMESTAMP_NTZ - when this row version was superseded (null = currently active)
        IMPORTANT: For current customer data, always filter: dbt_valid_to IS NULL

    silver.core_stores  (SCD2 snapshot of stores - track historical changes)
        store_id, open_date, country, state, square_meters,
        updated_at       TIMESTAMP_NTZ - when the record was last modified in the raw layer
        source_file      VARCHAR       - S3 bucket source (batch process)
        ingested_at      TIMESTAMP_NTZ - when data was loaded into Snowflake
        dbt_scd_id       VARCHAR       - unique MD5 hash identifying this row version
        dbt_updated_at   TIMESTAMP_NTZ - timestamp of the dbt snapshot run
        dbt_valid_from   TIMESTAMP_NTZ - when this row version became active
        dbt_valid_to     TIMESTAMP_NTZ - when this row version was superseded (null = currently active)
        IMPORTANT: For current store data, always filter: dbt_valid_to IS NULL

        

GOLD SCHEMA (pre-aggregated business metrics - use for executive analysis and trends):

  gold.agg_revenue - daily revenue KPIs
    period                         DATE         - calendar day
    total_active_users             NUMBER       - unique distinct customers who placed at least one order that day
    total_new_buyers               NUMBER       - unique customers who made their first-ever lifetime purchase that day
    total_returning_buyers         NUMBER       - unique customers who placed an order and had a previous purchase
    total_products_sold            NUMBER       - total individual product units sold across all transactions that day
    total_revenue_in_usd           FLOAT        - daily net revenue (total price - total product cost) in USD
    pct_change_in_daily_revenue    FLOAT        - percentage change in net revenue vs the previous day
    cumulative_revenue_last_7_days FLOAT        - rolling 7-day sum of net revenue (current day + previous 6) in USD
    top_country_by_revenue         VARCHAR      - country whose stores generated the highest total net revenue that day
    top_selling_product_by_order   VARCHAR      - product name with the highest volume of units sold that day
    top_selling_product_by_revenue VARCHAR      - product name that generated the highest net revenue that day

  gold.customer_360 - lifetime customer value & behaviour
    user_id                   NUMBER        UNIQUE - customer identifier
    profile_modification_count NUMBER       - total number of profile updates (excluding initial creation)
    user_name                 VARCHAR      - full legal name / display name
    gender                    VARCHAR      - gender
    date_of_birth             DATE         - date of birth
    continent                 VARCHAR      - continent of residence
    country                   VARCHAR      - country of residence
    state                     VARCHAR      - state/province
    city                      VARCHAR      - city
    unique_product_count      VARIANT       - JSON object mapping product_name → total ordered quantity
    total_products_ordered    NUMBER        - lifetime total individual product units ordered
    total_order_value         FLOAT         - lifetime gross monetary value of all purchases in USD
    average_order_price       FLOAT         - average gross price paid per product unit across all orders in USD
    net_revenue_on_user       FLOAT         - lifetime net profit (total price - total cost) from customer transactions in USD
    first_purchase_date       DATE          - calendar date of the very first order
    most_recent_purchase_date DATE          - calendar date of the most recent order
    days_since_last_purchase  NUMBER        - number of days from most recent purchase to current system date

  gold.agg_store_stats - store-level lifetime performance
    store_id                     NUMBER       - unique store identifier
    open_date                    DATE         - date the store opened
    country                      VARCHAR      - store country
    state                        VARCHAR      - store state/province
    square_meters                NUMBER       - physical footprint in square meters
    total_unique_buyers          NUMBER       - lifetime count of distinct customers who purchased at this store
    total_products_sold          NUMBER       - lifetime total product units sold by this store
    total_revenue_in_local_currency FLOAT     - lifetime net revenue in the local transaction currency
    total_revenue_in_usd         FLOAT        - lifetime net revenue converted to USD
    top_selling_product_by_order VARCHAR      - product with highest total units sold at this store
    top_selling_product_by_revenue VARCHAR     - product generating highest net revenue for this store

  gold.agg_product_stats - product-level lifetime performance
    product_id          NUMBER       - unique product variation/SKU
    sub_category        VARCHAR      - specific product subcategory
    brand               VARCHAR      - brand/manufacturer name
    product_name        VARCHAR      - descriptive product name
    unit_cost_in_usd    FLOAT        - production cost per unit in USD
    unit_price_in_usd   FLOAT        - standard list/retail price per unit in USD
    total_unique_buyers NUMBER       - lifetime count of distinct customers who purchased this product
    total_sold          NUMBER       - lifetime total units sold
    total_cost_in_usd   FLOAT        - lifetime accumulated cost of all sold units in USD
    total_price_in_usd  FLOAT        - lifetime gross sales revenue before cost deductions in USD
    total_revenue_in_usd FLOAT       - lifetime net profit (total price - total cost) in USD
    top_purchase_country VARCHAR     - country that recorded the highest volume of units sold for this product

  gold.sales_line_stats - enriched transactional data (every order line)
    user_id                    NUMBER       - customer who placed the order
    order_id                   NUMBER       - unique transaction identifier
    order_date                 DATE         - calendar date of purchase
    customer_type              VARCHAR      - 'first_time_buyer' or 'returning_buyer'
    line_item                  NUMBER       - sequential row/item number within the order
    product_id                 NUMBER       - product variation/SKU
    product_name               VARCHAR      - descriptive product name
    quantity                   NUMBER       - number of units purchased for this line item
    store_id                   NUMBER       - store or fulfillment channel (0 = online)
    store_location             VARCHAR      - country of the store
    is_walk_in_purchase        VARCHAR      - 'True' for in-store pickup/walk-in, 'False' for online/delivery
    delivery_date              DATE         - scheduled or actual delivery date; null for walk-ins
    unit_cost_in_usd           FLOAT        - production cost per unit in USD
    unit_price_in_usd          FLOAT        - retail list price per unit in USD
    total_cost_in_usd          FLOAT        - total production cost for the line (unit_cost * quantity)
    total_price_in_usd         FLOAT        - gross sales price for the line (unit_price * quantity)
    revenue_in_usd             FLOAT        - gross profit for the line (total_price - total_cost)
    currency_code              VARCHAR      - ISO currency code used for the transaction
    exchange_rate_to_dollar    FLOAT        - conversion rate from local currency to USD on that day
    total_price_in_local_currency FLOAT     - final transaction amount in the customer's local currency

  gold.ai_agent_summaries - previous AI agent summaries (read-only; do NOT write)
    summary_id   INTEGER AUTOINCREMENT PRIMARY KEY - unique summary ID
    summary      TEXT                               - executive summary text
    model        STRING                             - AI model that generated the summary
    generated_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP() - when the summary was created

Rules:
  - Always use fully qualified names: data_platform_db.schema.table
  - Snowflake SQL syntax only
  - store_id = 0 means online; store_id > 0 are physical stores.
  - delivery_date MUST be NULL for walk-in purchases (store_id > 0)
  - Only read gold.ai_agent_summaries; do NOT insert or update it. The system saves the summary automatically
  - For internal analysis you may retrieve up to 5000 rows
  
  """