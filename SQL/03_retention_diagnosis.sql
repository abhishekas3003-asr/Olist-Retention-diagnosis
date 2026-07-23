/* ============================================================================
   03_RETENTION_DIAGNOSIS.SQL  —  ACT 3: Why don't customers return,
   and can it be fixed?
   The centerpiece. Tests delivery experience as a retention lever (worked
   example), then BOUNDS how much of non-return it can explain (the headline).
   Claim types escalate: association -> association-under-control -> bounded.
   ============================================================================ */


/* ----------------------------------------------------------------------------
   Q10 (step 1) — delivery-delay distribution, to choose sensible buckets
   Claim type: description.
   Finding: median delay = -12 days (half of orders arrive 12+ days EARLY);
   p90 = -2 (at least 90% arrive early). "Late" is the rare exception, so the
   lever is "reduce the rare late tail," not "deliver faster overall."
   ---------------------------------------------------------------------------- */
WITH delivery_delay AS (
    SELECT
        (order_delivered_customer_date::date - order_estimated_delivery_date::date) AS delay_days
    FROM orders_clean
    WHERE order_delivered_customer_date IS NOT NULL
)
SELECT
    MIN(delay_days)                                                  AS min_delay,
    MAX(delay_days)                                                  AS max_delay,
    ROUND(AVG(delay_days), 2)                                        AS avg_delay,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY delay_days)         AS p25,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY delay_days)         AS median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY delay_days)         AS p75,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY delay_days)         AS p90
FROM delivery_delay;


/* ----------------------------------------------------------------------------
   Q10 (step 2) — delivery bucket → average review score
   Claim type: association.
   Finding: review score falls monotonically as delivery worsens:
   very_early 4.32 -> early 4.24 -> on_time 4.03 -> late 3.78. Real but MILD.
   [FIX #7] Pre-delivery reviews excluded (review must be dated on/after
   delivery, or it can't be rating the delivery experience).
   ---------------------------------------------------------------------------- */
WITH delivery_delay AS (
    SELECT
        order_id,
        order_delivered_customer_date,
        (order_delivered_customer_date::date - order_estimated_delivery_date::date) AS delay_days
    FROM orders_clean
    WHERE order_delivered_customer_date IS NOT NULL
)
SELECT
    CASE
        WHEN delay_days < -10 THEN 'very_early'
        WHEN delay_days < 0   THEN 'early'
        WHEN delay_days = 0   THEN 'on_time'
        ELSE 'late'
    END AS delivery_bucket,
    COUNT(*)                       AS reviews_counted,
    ROUND(AVG(r.review_score), 2)  AS avg_score
FROM delivery_delay d
JOIN order_reviews_clean r ON d.order_id = r.order_id
WHERE r.review_creation_date >= d.order_delivered_customer_date   -- [FIX #7]
GROUP BY 1
ORDER BY avg_score DESC;


/* ----------------------------------------------------------------------------
   Q10+ (cell-size check) — is state-level control safe?
   Claim type: validation.
   Finding: at the state level (27 states), the "late" bucket is far too thin
   in small states (e.g. AC=2, AP=2, AM=4). ~1/3 of cells below a usable floor,
   so state-level control would be noise. Fix: group into 5 macro-regions.
   ---------------------------------------------------------------------------- */
WITH first_orders AS (
    SELECT DISTINCT ON (c.customer_unique_id)
        c.customer_unique_id,
        c.customer_state,
        (o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date) AS delay_days
    FROM customers_clean c
    JOIN orders_clean o ON c.customer_id = o.customer_id
    WHERE o.order_delivered_customer_date IS NOT NULL
    ORDER BY c.customer_unique_id, o.order_purchase_timestamp
)
SELECT
    customer_state,
    CASE WHEN delay_days > 0 THEN 'late' ELSE 'not_late' END AS delivery_bucket,
    COUNT(*) AS first_orders
FROM first_orders
GROUP BY customer_state, delivery_bucket
ORDER BY customer_state, delivery_bucket;


/* ----------------------------------------------------------------------------
   Q10+ — First-delivery experience → return rate, CONTROLLED FOR REGION
   Claim type: association-under-control (region held fixed). NOT causal.
   Finding: in 4 of 5 regions, on-time first-deliveries return slightly more
   than late ones (gaps ~0.2-0.8 pts). Southeast (best-powered) 3.35 vs 2.55.
   North reverses but has only ~149 late customers = small-sample noise.
   Effect is real but MARGINAL.

   Pipeline: first delivered order per customer (DISTINCT ON) -> label region
   (5 macro-regions) + late/not_late -> join a returned flag (2+ orders) ->
   compare return rate within each region.
   ---------------------------------------------------------------------------- */
WITH first_orders AS (
    SELECT DISTINCT ON (c.customer_unique_id)
        c.customer_unique_id,
        c.customer_state,
        (o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date) AS delay_days
    FROM customers_clean c
    JOIN orders_clean o ON c.customer_id = o.customer_id
    WHERE o.order_delivered_customer_date IS NOT NULL
    ORDER BY c.customer_unique_id, o.order_purchase_timestamp
),
labeled AS (
    SELECT
        customer_unique_id,
        CASE
            WHEN customer_state IN ('AC','AP','AM','PA','RO','RR','TO')            THEN 'North'
            WHEN customer_state IN ('AL','BA','CE','MA','PB','PE','PI','RN','SE')  THEN 'Northeast'
            WHEN customer_state IN ('DF','GO','MS','MT')                          THEN 'Central_West'
            WHEN customer_state IN ('ES','MG','RJ','SP')                          THEN 'Southeast'
            WHEN customer_state IN ('PR','RS','SC')                               THEN 'South'
            ELSE 'unknown'
        END AS region,
        CASE WHEN delay_days > 0 THEN 'late' ELSE 'not_late' END AS delivery_bucket
    FROM first_orders
),
customer_returns AS (
    SELECT
        c.customer_unique_id,
        CASE WHEN COUNT(DISTINCT o.order_id) >= 2 THEN 1 ELSE 0 END AS returned
    FROM customers_clean c
    JOIN orders_clean o ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
)
SELECT
    l.region,
    l.delivery_bucket,
    COUNT(*)                          AS customers,
    ROUND(AVG(r.returned) * 100, 2)   AS return_rate_pct
FROM labeled l
JOIN customer_returns r ON l.customer_unique_id = r.customer_unique_id
GROUP BY l.region, l.delivery_bucket
ORDER BY l.region, l.delivery_bucket;


/* ----------------------------------------------------------------------------
   Q-BOUND — How much of total non-return can delivery explain?  ★ HEADLINE
   Claim type: bounded estimate (upper bound).
   Overall: late 6,349 custs / 2.60% return; not_late 87,007 / 3.23%.
   Counterfactual: if the 6,349 late customers returned at the 3.23% on-time
   rate instead of 2.60%, that 0.63pt gap recovers ~40 customers.
   Against ~90,000 non-returners, that is ~0.04% of the problem.
   => The retention crisis is STRUCTURAL, not operational. Upper bound: assumes
   the whole gap is caused by delivery, so the real effect is smaller.
   ---------------------------------------------------------------------------- */
WITH first_orders AS (
    SELECT DISTINCT ON (c.customer_unique_id)
        c.customer_unique_id,
        (o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date) AS delay_days
    FROM customers_clean c
    JOIN orders_clean o ON c.customer_id = o.customer_id
    WHERE o.order_delivered_customer_date IS NOT NULL
    ORDER BY c.customer_unique_id, o.order_purchase_timestamp
),
labeled AS (
    SELECT
        customer_unique_id,
        CASE WHEN delay_days > 0 THEN 'late' ELSE 'not_late' END AS delivery_bucket
    FROM first_orders
),
customer_returns AS (
    SELECT
        c.customer_unique_id,
        CASE WHEN COUNT(DISTINCT o.order_id) >= 2 THEN 1 ELSE 0 END AS returned
    FROM customers_clean c
    JOIN orders_clean o ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
)
SELECT
    l.delivery_bucket,
    COUNT(*)                          AS customers,
    SUM(r.returned)                   AS returners,
    ROUND(AVG(r.returned) * 100, 2)   AS return_rate_pct
FROM labeled l
JOIN customer_returns r ON l.customer_unique_id = r.customer_unique_id
GROUP BY l.delivery_bucket;


/* ----------------------------------------------------------------------------
   Q-SYNTH — Do high-value customers return more? (the one-timer dependency)
   Claim type: description + synthesis.
   Finding: return rate rises with spend (top tier 7.78% vs bottom 0.28%), but
   the top tier is still ~92% one-and-done. So there is no loyal high-value
   base, only high-value one-timers.
   Caveat: partial circularity: 2+ order customers sum more spend, so they land
   in higher tiers partly BECAUSE they returned. The 7.78% is real but inflated
   by this mechanism.
   ---------------------------------------------------------------------------- */
WITH customer_spend AS (
    SELECT
        c.customer_unique_id,
        SUM(oi.price + oi.freight_value)                                          AS revenue,
        NTILE(4) OVER (ORDER BY SUM(oi.price + oi.freight_value) DESC)            AS spend_quartile
    FROM customers_clean c
    JOIN orders_clean o       ON c.customer_id = o.customer_id
    JOIN order_items_clean oi ON o.order_id = oi.order_id
    GROUP BY c.customer_unique_id
),
customer_returns AS (
    SELECT
        c.customer_unique_id,
        CASE WHEN COUNT(DISTINCT o.order_id) >= 2 THEN 1 ELSE 0 END AS returned
    FROM customers_clean c
    JOIN orders_clean o ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
)
SELECT
    s.spend_quartile,
    COUNT(*)                          AS customers,
    ROUND(AVG(s.revenue), 2)          AS avg_spend,
    ROUND(AVG(r.returned) * 100, 2)   AS return_rate_pct
FROM customer_spend s
JOIN customer_returns r ON s.customer_unique_id = r.customer_unique_id
GROUP BY s.spend_quartile
ORDER BY s.spend_quartile;
