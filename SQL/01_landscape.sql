/* ============================================================================
   01_LANDSCAPE.SQL  —  ACT 1: Is this a healthy, growing business?
   Descriptive analysis of growth, revenue accumulation, and category mix.
   All findings here are DESCRIPTIONS (measured facts), no causal claims.
   ============================================================================ */


/* ----------------------------------------------------------------------------
   TIME RANGE — what window does the data actually cover?
   Establishes the trustworthy analysis window (data thins at both ends).
   ---------------------------------------------------------------------------- */
SELECT
    min(order_purchase_timestamp) AS first_order,
    max(order_purchase_timestamp) AS last_order
FROM orders_clean;


/* ----------------------------------------------------------------------------
   REVENUE VALIDATION — the fan-out double-count catch
   Claim type: methodology check.
   Finding: joining orders -> items AND payments in one query multiplies each
   item row by the number of payment rows, inflating revenue by 4.6%
   (R$16.57M wrong vs R$15.84M correct). Revenue is an ITEM-grain measure and
   must be summed from order_items alone. Every revenue figure below uses the
   correct grain.
   ---------------------------------------------------------------------------- */

-- WRONG: items joined to payments fans out the item rows.
SELECT SUM(oi.price + oi.freight_value) AS revenue_wrong
FROM orders_clean o
JOIN order_items_clean oi    ON o.order_id = oi.order_id
JOIN order_payments_clean op ON o.order_id = op.order_id;   -- => R$16,566,543.85

-- RIGHT: revenue computed at item grain only.
SELECT SUM(oi.price + oi.freight_value) AS revenue_right
FROM order_items_clean oi;                                   -- => R$15,843,553.24


/* ----------------------------------------------------------------------------
   Q1 — Monthly volume + revenue, and month-over-month growth
   Claim type: description.
   Finding: steady growth across the trustworthy window (Jan 2017 - Aug 2018).
   The soft-launch tail (2016) and the censored final months (Sep-Oct 2018)
   produce meaningless MoM swings on tiny bases and are read with that caveat.
   ---------------------------------------------------------------------------- */
SELECT
    month,
    revenue,
    LAG(revenue) OVER (ORDER BY month) AS previous_month_revenue,
    ROUND((revenue / LAG(revenue) OVER (ORDER BY month) - 1) * 100, 2) AS mom_growth_pct
FROM (
    SELECT
        DATE_TRUNC('month', o.order_purchase_timestamp) AS month,
        COUNT(DISTINCT o.order_id)         AS monthly_volume,
        SUM(oi.price + oi.freight_value)   AS revenue
    FROM orders_clean o
    JOIN order_items_clean oi ON o.order_id = oi.order_id
    GROUP BY month
) t
ORDER BY month;


/* ----------------------------------------------------------------------------
   Q1b — 3-month moving average of revenue
   Claim type: description.
   Finding: smooths the monthly noise to show the underlying growth trend.
   (Read only inside the trustworthy window; the smoothing blends the
   censored tail upward if extended to the final months.)
   ---------------------------------------------------------------------------- */
SELECT
    month,
    revenue,
    AVG(revenue) OVER (ORDER BY month
                       ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS revenue_3month_moving_avg
FROM (
    SELECT
        DATE_TRUNC('month', o.order_purchase_timestamp) AS month,
        SUM(oi.price + oi.freight_value) AS revenue
    FROM orders_clean o
    JOIN order_items_clean oi ON o.order_id = oi.order_id
    GROUP BY month
) t
ORDER BY month;


/* ----------------------------------------------------------------------------
   Q3 — Cumulative revenue (running total)
   Claim type: description.
   Finding: the running total reconciles exactly to R$15,843,553.24, matching
   the item-grain total above. A built-in consistency check: two independent
   query paths agree, confirming the revenue figure.
   ---------------------------------------------------------------------------- */
SELECT
    month,
    revenue,
    SUM(revenue) OVER (ORDER BY month
                       ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total_revenue
FROM (
    SELECT
        DATE_TRUNC('month', o.order_purchase_timestamp) AS month,
        SUM(oi.price + oi.freight_value) AS revenue
    FROM orders_clean o
    JOIN order_items_clean oi ON o.order_id = oi.order_id
    GROUP BY month
) t
ORDER BY month;


/* ----------------------------------------------------------------------------
   Q6 — Category revenue concentration (Pareto)
   Claim type: description.
   Finding: 18 of 74 categories generate 80% of revenue. Real concentration,
   though milder than a literal 80/20 (it takes ~24% of categories, not 20%).
   ---------------------------------------------------------------------------- */
SELECT
    product_category,
    revenue,
    SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING) AS running_total,
    ROUND(
        SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING)
        / SUM(revenue) OVER () * 100
    , 2) AS cumulative_pct
FROM (
    SELECT
        p.product_category_name AS product_category,
        SUM(oi.price + oi.freight_value) AS revenue
    FROM order_items_clean oi
    JOIN products_clean p ON oi.product_id = p.product_id
    GROUP BY p.product_category_name
) t
ORDER BY revenue DESC;
