# Traceability Matrix — Olist Customer Value Analysis

This matrix maps every business question to its SQL method, the **type of claim** the result can support, the finding, and the honest caveats. The claim-type column is deliberate: it states what each query is permitted to assert, and what it is not.

**Claim types used:**
- **Description** — a measured fact about what is. No causation implied.
- **Association** — two things move together. No control for confounders.
- **Association-under-control** — a relationship that holds when a confounder is held fixed. Still not proof of causation.
- **Bounded estimate** — a deliberately conservative ceiling on an effect's size.

**Canonical figure (reused throughout):** total revenue = **R$15,843,553.24** (items-only, `SUM(price + freight_value)` at item grain).

---

## Foundation — Schema & Validation Gate

| Step | Method | Claim type | Result | Caveats / notes |
|---|---|---|---|---|
| Bronze→silver pipeline | `CREATE TABLE ... AS SELECT`, typed casts, `NULLIF(col,'')::type` | — | 9 raw + 9 clean tables, row-count verified against known Olist sizes | Loaded as text first so strict types couldn't silently reject blank (meaningful-NULL) delivery dates |
| Geolocation dedup | `GROUP BY zip`, `AVG` centroid, `MIN` city/state | Description | 1,000,163 → 19,015 rows (~98% redundant) | Deduped to prevent ~52× fan-out on the zip join; city pick arbitrary-but-defensible (analysis groups by state) |

---

## Act 1 — The Landscape *(all description)*

| Q | Business question | Method | Claim type | Finding | Caveats |
|---|---|---|---|---|---|
| Q1 | How did volume & revenue grow month-over-month? | `DATE_TRUNC`, `LAG() OVER`, MoM % | Description | Steady growth; trustworthy window **Jan 2017–Aug 2018** | 2016 soft-launch & Sep–Oct 2018 censored tail give nonsense MoM % (+699,127%, −99.98%) from small bases → trimmed |
| Q1b | What's the underlying trend, smoothed? | `AVG() OVER (ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)` | Description | 3-mo moving average clarifies trend | Smoothing launders the censored tail (blends Sep-2018 crater up to ~R$687K) → read only inside the window |
| Q3 | How does revenue accumulate over time? | `SUM() OVER (... ROWS UNBOUNDED PRECEDING)` | Description | Cumulative curve reconciles **exactly** to R$15,843,553.24 | Exact reconciliation = internal consistency check passed (two query paths agree) |
| Q6 | How concentrated is revenue across categories? | category rev / `SUM() OVER ()`, cumulative % | Description | **18 of 74 categories = 80% of revenue** | Stated as a number, not "concentrated." Concentration is real but milder than literal 80/20 (~25/80) |

---

## Act 2 — The Concentration Problem *(description; the retention crisis is established here)*

| Q | Business question | Method | Claim type | Finding | Caveats |
|---|---|---|---|---|---|
| Q5 | Is revenue hostage to a few sellers? | `NTILE(10) OVER (ORDER BY revenue DESC)`, decile share | Description | **Top 10% of sellers = 66.76% of revenue**; top 30% = 89.88%; bottom 50% ≈ 3.4% | Framed as a "risk to monitor," NOT a verdict of good/bad (concentration can be efficient). Gini deferred — decile share sufficient |
| Q8 | Can we segment customers by value? (RFM) | RFM **reframed**: frequency diagnosis → `NTILE(4)` Monetary tiers + binary repeat-flag | Description | **96.88% bought exactly once** → frequency axis degenerate → adapted, not forced. Top 25% of customers = ~60% of revenue. Repeat buyers 3.05% custs / 5.71% revenue | The ~1.9× repeat multiple is **near-tautological** (2+ orders ⇒ ~2× spend) — flagged, NOT presented as a finding. Recency demoted to a censoring caveat. **This is the showpiece of analytical judgment** (adapt method to data) |
| Q2 | Which categories are rising vs dying? | matched-window (Jan–Aug both yrs) `SUM(CASE WHEN year...)`, vs platform tide | Description | Platform tide +141%; of 25 floor-passing categories, **10 gaining share / 15 losing share** | Matched window chosen for censoring fairness. Revenue floor (≥R$25K) chosen from a **visible break in the data**, not arbitrarily. "Losing share" ≠ "dying" (all still grew in raw R$). NULL-category bucket (~R$145K) excluded |

---

## Act 3 — The Retention Diagnosis *(the centerpiece)*

| Q | Business question | Method | Claim type | Finding | Caveats |
|---|---|---|---|---|---|
| Q10 | Does delivery quality affect satisfaction? | delay buckets (`delivered::date − estimated::date`), `AVG(review_score)`, **pre-delivery reviews excluded** | **Association** | Monotonic: very_early 4.32 → early 4.24 → on_time 4.03 → late 3.78 | Pre-delivery review exclusion [FIX #7] applied (late reviews 6,535→1,050). ~93% delivered EARLY → lever is "reduce the rare late tail," not "be faster." Punishment is mild |
| Q10+ | Does a bad first delivery reduce return rate? | first order (`DISTINCT ON`), late-vs-not, return flag, **controlled for region** | **Association-under-control** | Late first-delivery associated with ~0.5pt lower return, holding region fixed (Southeast, best-powered: 3.35 vs 2.55) | **NOT causal.** State-level control too thin → dropped to **5 macro-regions** after checking cell sizes [AUDIT-5]. North reverses but ~149 late custs ⇒ small-sample noise, **flagged not hidden** |
| **Q-bound** | **How much of non-return can delivery even explain?** | controlled gap × affected population vs total non-returners | **Bounded estimate** | ★ **Fixing every late delivery recovers ~40 customers = ~0.04% of the non-return problem.** The crisis is **structural, not logistics** | **Upper bound** (assumes fixing ALL late, best case) → real effect ≤ this. The headline: delivery is a real but marginal lever; 96.88% one-and-done is not a delivery problem |
| Q-synth | Is the platform dependent on high-value one-timers? | spend quartiles × return flag | Description + synthesis | Return rate rises with spend (top 7.78% vs bottom 0.28%), but top tier still **~92% one-and-done** | **Partial circularity flagged**: repeat buyers sum more spend, so they land in higher tiers partly *because* they returned → 7.78% real but inflated. Insight: no loyal high-value base, only high-value one-timers |
| Q-value | What's the fix worth in R$? | — | — | **CUT** | An R$ figure on ~40 customers (~R$5–15K on R$15.8M) would undercut the "0.04%" headline. Percentage is the stronger punchline |

---

## Data-Mess Wrestling (Appendix B index)

Issues found and handled, in order of appearance:
1. **Revenue double-count** (items×payments fan-out): R$16,566,543.85 wrong vs R$15,843,553.24 right (4.6% inflation, multi-payment driven; small size = the danger).
2. **`customer_id` vs `customer_unique_id`**: using the per-order id fabricates a 0% retention rate; all retention work keys off `customer_unique_id`.
3. **Geolocation duplication**: 1M+ rows → 19,015 centroids; prevents zip-join fan-out.
4. **Meaningful NULL delivery dates**: undelivered/cancelled orders preserved via text-load + `NULLIF`, excluded only where a delivery is required.
5. **Pre-delivery reviews**: excluded from Q10 (a review before arrival can't rate the delivery).
6. **Itemless-orders discrepancy**: 676-customer / 775-order gap diagnosed via **staged counts + anti-join** (`LEFT JOIN ... IS NULL`); cancelled orders, excluded from spend.
7. **NULL category bucket**: ~R$145K of untagged products excluded from category analysis.
8. **Small-base distortion**: tiny categories/months produce meaningless % → revenue floor + trimmed window.
9. **Cell-size thinness**: state-level control left ~1/3 of cells below floor → coarsened to 5 macro-regions.

---

## What was deliberately NOT done
- **No cohort / churn / CLV** — 96.88% one-and-done makes these degenerate on this data.
- **No ML / regression** — controls done via multi-dimensional `GROUP BY`, appropriate to the questions asked.
- **No bare causal claims** — strongest claim is "association-under-control"; no query gets a causal verb it didn't earn.
