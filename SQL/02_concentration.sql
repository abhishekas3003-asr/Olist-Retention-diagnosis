/* ============================================================================
   02_CONCENTRATION.SQL  —  ACT 2: Who carries the business?
   Seller, customer, and category concentration. The retention crisis
   (96.88% one-and-done) first surfaces here, in the customer analysis.
   All findings are DESCRIPTIONS unless noted.
   ============================================================================ */


/* ----------------------------------------------------------------------------
   Q5 — Seller concentration (NTILE deciles)
   Claim type: description.
   Finding: the top 10% of sellers generate 66.76% of revenue; top 30% = 89.88%.
   Framed as a concentration RISK to monitor, not a good/bad verdict.
   ---------------------------------------------------------------------------- */
WITH seller_revenue AS (
    SELECT seller_id, SUM(price + freight_value) AS revenue
    FROM order_items_clean
    GROUP BY seller_id
),
bucketed AS (
    SELECT
        seller_id,
        revenue,
        NTILE(10) OVER (ORDER BY revenue DESC) AS decile
    FROM seller_revenue
)
SELECT
    decile,
    COUNT(*)                                              AS sellers_in_decile,
    SUM(revenue)                                          AS decile_revenue,
    ROUND(SUM(revenue) / SUM(SUM(revenue)) OVER () * 100, 2) AS pct_of_total
FROM bucketed
GROUP BY decile
ORDER BY decile;


/* ----------------------------------------------------------------------------
   Q8 (diagnosis step) — purchase-frequency distribution
   Claim type: description.
   Finding: 96.88% of customers bought exactly once. THIS is the thesis of the
   whole project, and it's why a standard RFM segmentation had to be adapted:
   the Frequency axis has almost no variation to segment on.
   Note: keys on customer_unique_id (per-person), NOT customer_id (per-order).
   ---------------------------------------------------------------------------- */
WITH customer_purchase_count AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS purchase_count
    FROM customers_clean c
    JOIN orders_clean o ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
)
SELECT
    purchase_count,
    COUNT(*) AS number_of_customers
FROM customer_purchase_count
GROUP BY purchase_count
ORDER BY purchase_count;


/* ----------------------------------------------------------------------------
   DATA-QUALITY CHECK — the 676-row discrepancy
   Claim type: validation.
   Check A counts customers reachable via orders; Check B counts orders with NO
   matching items (an anti-join). The itemless orders are cancelled/incomplete
   and carry no revenue, explaining the row gap. Diagnosed before trusting spend.
   ---------------------------------------------------------------------------- */
-- Check A: customers reachable through orders
SELECT COUNT(DISTINCT c.customer_unique_id)
FROM customers_clean c
JOIN orders_clean o ON c.customer_id = o.customer_id;

-- Check B: orders with no matching order_items (anti-join)
SELECT COUNT(*)
FROM orders_clean o
LEFT JOIN order_items_clean oi ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL;


/* ----------------------------------------------------------------------------
   Q8 — Monetary segmentation (the RFM reframe)
   Claim type: description.
   Finding: top 25% of customers by spend drive ~60% of revenue.
   Frequency was degenerate (above), so RFM was adapted to Monetary quartiles
   plus a binary repeat-flag (below) instead of a full 5x5x5 grid.
   ---------------------------------------------------------------------------- */
WITH customer_spend AS (
    SELECT c.customer_unique_id, SUM(oi.price + oi.freight_value) AS revenue
    FROM customers_clean c
    JOIN orders_clean o        ON c.customer_id = o.customer_id
    JOIN order_items_clean oi  ON o.order_id = oi.order_id
    GROUP BY c.customer_unique_id
),
bucketed AS (
    SELECT customer_unique_id, revenue,
           NTILE(4) OVER (ORDER BY revenue DESC) AS spend_quartile
    FROM customer_spend
)
SELECT
    spend_quartile,
    COUNT(*)                                                AS customers,
    ROUND(SUM(revenue), 2)                                  AS tier_revenue,
    ROUND(SUM(revenue) / SUM(SUM(revenue)) OVER () * 100, 2) AS pct_of_revenue,
    ROUND(AVG(revenue), 2)                                  AS avg_spend
FROM bucketed
GROUP BY spend_quartile
ORDER BY spend_quartile;


/* ----------------------------------------------------------------------------
   Q8 — Repeat-flag (the adapted Frequency axis)
   Claim type: description.
   Finding: repeat buyers are ~3.05% of customers / ~5.71% of revenue.
   (The ~1.9x revenue-vs-customer ratio is near-tautological, since 2+ orders
   means ~2x spend, so it is NOT reported as a disproportionality finding.)
   ---------------------------------------------------------------------------- */
WITH customer_order AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id)        AS order_count,
        SUM(oi.price + oi.freight_value)  AS revenue
    FROM customers_clean c
    JOIN orders_clean o       ON c.customer_id = o.customer_id
    JOIN order_items_clean oi ON o.order_id = oi.order_id
    GROUP BY c.customer_unique_id
)
SELECT
    CASE WHEN order_count >= 2 THEN 'repeat' ELSE 'one_time' END AS buyer_type,
    COUNT(*)                                                     AS customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)           AS pct_of_customers,
    ROUND(SUM(revenue) / SUM(SUM(revenue)) OVER () * 100, 2)     AS pct_of_revenue
FROM customer_order
GROUP BY CASE WHEN order_count >= 2 THEN 'repeat' ELSE 'one_time' END;


/* ----------------------------------------------------------------------------
   Q2 — Category share shift, YoY (rising vs losing share)
   Claim type: description.
   Method: matched Jan-Aug window for BOTH years (2018 is censored mid-Oct, so
   comparing full years would be unfair). NULL-category products excluded.
   Platform "tide" = +141.04% growth (computed across all categories). Each
   category is then rated against that benchmark, but only if it cleared a
   revenue floor of R$25,000 in 2017 (below that, % growth is noise from a
   tiny base). Result: 10 categories gaining share, 15 losing share.
   ---------------------------------------------------------------------------- */

-- Step 1: platform-wide growth (the benchmark / "tide")
WITH category_comparison AS (
    SELECT
        product_category_name,
        SUM(CASE WHEN order_year = 2017 THEN revenue ELSE 0 END) AS rev_2017,
        SUM(CASE WHEN order_year = 2018 THEN revenue ELSE 0 END) AS rev_2018
    FROM (
        SELECT
            p.product_category_name,
            EXTRACT(YEAR FROM o.order_purchase_timestamp) AS order_year,
            SUM(oi.price + oi.freight_value) AS revenue
        FROM orders_clean o
        JOIN order_items_clean oi ON o.order_id = oi.order_id
        JOIN products_clean p     ON oi.product_id = p.product_id
        WHERE EXTRACT(YEAR FROM o.order_purchase_timestamp) IN (2017, 2018)
          AND EXTRACT(MONTH FROM o.order_purchase_timestamp) BETWEEN 1 AND 8
          AND p.product_category_name IS NOT NULL
        GROUP BY p.product_category_name, order_year
    ) t
    GROUP BY product_category_name
)
SELECT
    SUM(rev_2017) AS total_2017,
    SUM(rev_2018) AS total_2018,
    ROUND((SUM(rev_2018) - SUM(rev_2017)) / SUM(rev_2017) * 100, 2) AS platform_growth
FROM category_comparison;   -- => +141.04%

-- Step 2: rate each floor-passing category as gaining or losing share vs +141.04%
WITH category_comparison AS (
    SELECT
        product_category_name,
        SUM(CASE WHEN order_year = 2017 THEN revenue ELSE 0 END) AS rev_2017,
        SUM(CASE WHEN order_year = 2018 THEN revenue ELSE 0 END) AS rev_2018
    FROM (
        SELECT
            p.product_category_name,
            EXTRACT(YEAR FROM o.order_purchase_timestamp) AS order_year,
            SUM(oi.price + oi.freight_value) AS revenue
        FROM orders_clean o
        JOIN order_items_clean oi ON o.order_id = oi.order_id
        JOIN products_clean p     ON oi.product_id = p.product_id
        WHERE EXTRACT(YEAR FROM o.order_purchase_timestamp) IN (2017, 2018)
          AND EXTRACT(MONTH FROM o.order_purchase_timestamp) BETWEEN 1 AND 8
          AND p.product_category_name IS NOT NULL
        GROUP BY p.product_category_name, order_year
    ) t
    GROUP BY product_category_name
)
SELECT
    product_category_name,
    rev_2017,
    rev_2018,
    ROUND((rev_2018 - rev_2017) / NULLIF(rev_2017, 0) * 100, 2) AS growth_rate,
    CASE
        WHEN (rev_2018 - rev_2017) / NULLIF(rev_2017, 0) * 100 >= 141.04
             THEN 'gaining share'
        ELSE 'losing share'
    END AS share_trend
FROM category_comparison
WHERE rev_2017 >= 25000          -- revenue floor: below this, % growth is noise
ORDER BY growth_rate DESC;
