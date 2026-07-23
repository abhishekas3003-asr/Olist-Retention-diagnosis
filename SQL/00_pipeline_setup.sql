/* ============================================================================
   00_PIPELINE_SETUP.SQL
   Bronze -> Silver pipeline: raw load, type casting, and cleaning.

   Design choice: every raw table is loaded as VARCHAR first (the "bronze"
   layer), then cast into a typed "silver" layer (_clean tables). Loading as
   text first is deliberate: a strict-typed load would reject or choke on the
   empty strings in date columns (e.g. orders that were never delivered).
   Loading loose, then casting with NULLIF, preserves those meaningful blanks
   as NULLs instead of losing the rows.
   ============================================================================ */


/* ----------------------------------------------------------------------------
   BRONZE LAYER — raw tables, all columns VARCHAR
   ---------------------------------------------------------------------------- */

CREATE TABLE orders (
    order_id                      varchar,
    customer_id                   varchar,
    order_status                  varchar,
    order_purchase_timestamp      varchar,
    order_approved_at             varchar,
    order_delivered_carrier_date  varchar,
    order_delivered_customer_date varchar,
    order_estimated_delivery_date varchar
);

CREATE TABLE order_items (
    order_id           varchar,
    order_item_id      varchar,
    product_id         varchar,
    seller_id          varchar,
    shipping_limit_date varchar,
    price              varchar,
    freight_value      varchar
);

CREATE TABLE order_payments (
    order_id             varchar,
    payment_sequential   varchar,
    payment_type         varchar,
    payment_installments varchar,
    payment_value        varchar
);

CREATE TABLE order_reviews (
    review_id              varchar,
    order_id               varchar,
    review_score           varchar,
    review_comment_title   varchar,
    review_comment_message varchar,
    review_creation_date   varchar,
    review_answer_timestamp varchar
);

-- Note: Olist ships real typos in the source columns ("lenght"); kept as-is
-- in bronze to match the raw CSV headers exactly.
CREATE TABLE products (
    product_id                 varchar,
    product_category_name      varchar,
    product_name_lenght        varchar,
    product_description_lenght varchar,
    product_photos_qty         varchar,
    product_weight_g           varchar,
    product_length_cm          varchar,
    product_height_cm          varchar,
    product_width_cm           varchar
);

CREATE TABLE customers (
    customer_id              varchar,
    customer_unique_id       varchar,
    customer_zip_code_prefix varchar,
    customer_city            varchar,
    customer_state           varchar
);

CREATE TABLE sellers (
    seller_id              varchar,
    seller_zip_code_prefix varchar,
    seller_city            varchar,
    seller_state           varchar
);

CREATE TABLE geolocation (
    geolocation_zip_code_prefix varchar,
    geolocation_lat             varchar,
    geolocation_lng             varchar,
    geolocation_city            varchar,
    geolocation_state           varchar
);

CREATE TABLE product_category_name_translation (
    product_category_name         varchar,
    product_category_name_english varchar
);


/* ----------------------------------------------------------------------------
   LOAD VALIDATION — row counts per table, checked against known Olist sizes
   ---------------------------------------------------------------------------- */

SELECT 'orders' AS tbl, count(*) FROM orders
UNION ALL SELECT 'order_items',   count(*) FROM order_items
UNION ALL SELECT 'order_payments', count(*) FROM order_payments
UNION ALL SELECT 'order_reviews',  count(*) FROM order_reviews
UNION ALL SELECT 'products',       count(*) FROM products
UNION ALL SELECT 'customers',      count(*) FROM customers
UNION ALL SELECT 'sellers',        count(*) FROM sellers
UNION ALL SELECT 'geolocation',    count(*) FROM geolocation
UNION ALL SELECT 'product_category_name_translation', count(*)
         FROM product_category_name_translation;


/* ----------------------------------------------------------------------------
   SILVER LAYER — typed, cleaned tables (_clean)
   NULLIF(col, '') converts empty strings to NULL before casting, so that
   meaningful blanks (e.g. undelivered orders) survive as NULL rather than
   breaking the cast.
   ---------------------------------------------------------------------------- */

CREATE TABLE orders_clean AS
SELECT
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp::timestamp                       AS order_purchase_timestamp,
    NULLIF(order_approved_at, '')::timestamp                  AS order_approved_at,
    NULLIF(order_delivered_carrier_date, '')::timestamp       AS order_delivered_carrier_date,
    NULLIF(order_delivered_customer_date, '')::timestamp      AS order_delivered_customer_date,
    order_estimated_delivery_date::timestamp                  AS order_estimated_delivery_date
FROM orders;

CREATE TABLE order_items_clean AS
SELECT
    order_id,
    order_item_id,
    product_id,
    seller_id,
    shipping_limit_date::timestamp AS shipping_limit_date,
    price::numeric                 AS price,
    freight_value::numeric         AS freight_value
FROM order_items;

CREATE TABLE order_payments_clean AS
SELECT
    order_id,
    payment_sequential,
    payment_type,
    payment_installments::int AS payment_installments,
    payment_value::numeric    AS payment_value
FROM order_payments;

CREATE TABLE order_reviews_clean AS
SELECT
    review_id,
    order_id,
    review_score::int AS review_score,
    review_comment_title,
    review_comment_message,
    NULLIF(review_creation_date, '')::timestamp   AS review_creation_date,
    NULLIF(review_answer_timestamp, '')::timestamp AS review_answer_timestamp
FROM order_reviews;

CREATE TABLE products_clean AS
SELECT
    product_id,
    product_category_name,
    NULLIF(product_name_lenght, '')::int        AS product_name_lenght,
    NULLIF(product_description_lenght, '')::int AS product_description_lenght,
    NULLIF(product_photos_qty, '')::int         AS product_photos_qty,
    NULLIF(product_weight_g, '')::numeric       AS product_weight_g,
    NULLIF(product_length_cm, '')::numeric      AS product_length_cm,
    NULLIF(product_height_cm, '')::numeric      AS product_height_cm,
    NULLIF(product_width_cm, '')::numeric       AS product_width_cm
FROM products;

-- customers / sellers / translation: all-text, no casts needed, but promoted
-- to the silver layer so every downstream query reads from one clean base.
CREATE TABLE customers_clean AS
SELECT
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
FROM customers;

CREATE TABLE sellers_clean AS
SELECT
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
FROM sellers;

CREATE TABLE product_category_name_translation_clean AS
SELECT
    product_category_name,
    product_category_name_english
FROM product_category_name_translation;


/* ----------------------------------------------------------------------------
   GEOLOCATION DEDUP
   The raw geolocation table has ~1M rows: many lat/lng points per zip prefix.
   Left un-deduped, joining on zip prefix would fan out every matched row.
   Collapse to one centroid row per zip prefix (~19K rows) before any join.
   ---------------------------------------------------------------------------- */

-- Diagnosis: how bad is the duplication?
SELECT
    count(*)                                  AS total_geolocation_rows,
    count(DISTINCT geolocation_zip_code_prefix) AS distinct_zip_prefixes
FROM geolocation;

-- Fix: one averaged centroid per zip prefix.
CREATE TABLE geolocation_clean AS
SELECT
    geolocation_zip_code_prefix,
    AVG(geolocation_lat::numeric) AS geolocation_lat,
    AVG(geolocation_lng::numeric) AS geolocation_lng,
    MIN(geolocation_city)         AS geolocation_city,
    MIN(geolocation_state)        AS geolocation_state
FROM geolocation
GROUP BY geolocation_zip_code_prefix;
