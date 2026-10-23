-- Lab 1 objects (adapted: AI_WORKSHOP_DB -> SNOWFLAKE_LEARNING_DB, WORKSHOP_WH -> SNOWFLAKE_LEARNING_WH)
USE ROLE SNOWFLAKE_LEARNING_ROLE;
USE WAREHOUSE SNOWFLAKE_LEARNING_WH;

CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_LEARNING_DB.SAISRISATYA_AI_RAG_DATA;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_LEARNING_DB.SAISRISATYA_AI_ANALYTICS;
CREATE STAGE IF NOT EXISTS SNOWFLAKE_LEARNING_DB.SAISRISATYA_AI_RAG_DATA.DOCS_STAGE DIRECTORY = (ENABLE = TRUE) ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

-- Module 1 Step 4: FEATURE_DOCS (15 rows, loaded from the notebook's rows list)

-- Module 2 Step 1: chunk 1500 / overlap 200
CREATE OR REPLACE TABLE SNOWFLAKE_LEARNING_DB.SAISRISATYA_AI_RAG_DATA.CHUNKED_DOCS AS
SELECT d.FEATURE_NAME, c.VALUE::VARCHAR AS CHUNK_TEXT
FROM SNOWFLAKE_LEARNING_DB.SAISRISATYA_AI_RAG_DATA.FEATURE_DOCS d,
     LATERAL FLATTEN(INPUT => SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(d.CONTENT, 'none', 1500, 200)) c;

-- Module 2 Step 2
CREATE OR REPLACE CORTEX SEARCH SERVICE SNOWFLAKE_LEARNING_DB.SAISRISATYA_AI_RAG_DATA.FEATURE_SEARCH_SERVICE
  ON CHUNK_TEXT
  ATTRIBUTES FEATURE_NAME
  WAREHOUSE = SNOWFLAKE_LEARNING_WH
  TARGET_LAG = '1 minute'
  EMBEDDING_MODEL = 'snowflake-arctic-embed-l-v2.0'
  AS (SELECT CHUNK_TEXT, FEATURE_NAME FROM SNOWFLAKE_LEARNING_DB.SAISRISATYA_AI_RAG_DATA.CHUNKED_DOCS);

-- Module 3 Step 5
CREATE OR REPLACE SEMANTIC VIEW SNOWFLAKE_LEARNING_DB.SAISRISATYA_AI_ANALYTICS.TPCH_ORDER_ANALYTICS
  TABLES (
    line_items AS SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM PRIMARY KEY (L_ORDERKEY, L_LINENUMBER)
      COMMENT = 'Line items - one row per product per order',
    orders AS SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS PRIMARY KEY (O_ORDERKEY)
      COMMENT = 'Customer orders',
    customers AS SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER PRIMARY KEY (C_CUSTKEY)
      COMMENT = 'Customer master data',
    nations AS SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION PRIMARY KEY (N_NATIONKEY)
      COMMENT = 'Nation reference',
    regions AS SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION PRIMARY KEY (R_REGIONKEY)
      COMMENT = 'Region reference',
    partsupp AS SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.PARTSUPP PRIMARY KEY (PS_PARTKEY, PS_SUPPKEY)
      COMMENT = 'Part-supplier cost data'
  )
  RELATIONSHIPS (
    line_items_to_orders AS line_items (L_ORDERKEY) REFERENCES orders (O_ORDERKEY),
    orders_to_customers AS orders (O_CUSTKEY) REFERENCES customers (C_CUSTKEY),
    customers_to_nations AS customers (C_NATIONKEY) REFERENCES nations (N_NATIONKEY),
    nations_to_regions AS nations (N_REGIONKEY) REFERENCES regions (R_REGIONKEY),
    line_items_to_partsupp AS line_items (L_PARTKEY, L_SUPPKEY) REFERENCES partsupp (PS_PARTKEY, PS_SUPPKEY)
  )
  FACTS (
    line_items.discounted_price AS L_EXTENDEDPRICE * (1 - L_DISCOUNT)
      COMMENT = 'Net price after discount per line item',
    line_items.quantity AS L_QUANTITY
      COMMENT = 'Quantity ordered per line item',
    partsupp.supply_cost AS PS_SUPPLYCOST
      COMMENT = 'Unit cost we pay the supplier'
  )
  DIMENSIONS (
    orders.order_date AS O_ORDERDATE WITH SYNONYMS = ('order date', 'purchase date') COMMENT = 'Date placed',
    orders.order_year AS YEAR(O_ORDERDATE) COMMENT = 'Year placed',
    customers.customer_name AS C_NAME WITH SYNONYMS = ('customer name') COMMENT = 'Customer name',
    customers.market_segment AS C_MKTSEGMENT
      WITH SYNONYMS = ('market segment', 'segment')
      COMMENT = 'AUTOMOBILE, BUILDING, FURNITURE, HOUSEHOLD, MACHINERY',
    nations.nation_name AS N_NAME WITH SYNONYMS = ('country', 'nation') COMMENT = 'Nation name',
    regions.region_name AS R_NAME WITH SYNONYMS = ('region', 'continent')
      COMMENT = 'AFRICA, AMERICA, ASIA, EUROPE, MIDDLE EAST'
  )
  METRICS (
    line_items.total_revenue AS SUM(line_items.discounted_price)
      WITH SYNONYMS = ('revenue', 'net revenue', 'sales')
      COMMENT = 'Total revenue: SUM(extended_price * (1 - discount))',
    line_items.total_cost_of_goods AS SUM(partsupp.supply_cost * line_items.quantity)
      WITH SYNONYMS = ('COGS', 'cost of goods sold', 'cost of goods')
      COMMENT = 'Total cost of goods: SUM(supplier_cost * quantity)',
    line_items.total_profit AS SUM(line_items.discounted_price - partsupp.supply_cost * line_items.quantity)
      WITH SYNONYMS = ('profit', 'gross profit', 'margin')
      COMMENT = 'Profit: revenue minus COGS',
    orders.order_count AS COUNT(DISTINCT O_ORDERKEY)
      WITH SYNONYMS = ('number of orders')
      COMMENT = 'Distinct order count',
    customers.customer_count AS COUNT(DISTINCT C_CUSTKEY)
      COMMENT = 'Distinct customer count'
  )
  COMMENT = 'Order analytics over TPC-H. Encodes revenue, COGS, and profit formulas.'
;
