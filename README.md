# Olist Marketplace: A Retention Diagnosis

**A Brazilian e-commerce marketplace grew to R$15.8M in revenue while losing 97% of its customers after a single purchase. This project asks whether that retention crisis was fixable, and finds that it wasn't.**

---

Between 2016 and 2018, the Olist marketplace grew fast and generated R$15.8M in revenue. It also lost 96.88% of its customers after one order.

This project asks the question that number raises: **is that retention crisis fixable, or structural?** I tested the most actionable candidate lever (first-order delivery experience) and found that fixing every late delivery company-wide would recover roughly 40 customers, about 0.04% of the non-return problem. The crisis isn't logistics. It's structural. Growth here comes almost entirely from new customers, with almost nothing bringing old ones back.

> **A note on the data that shaped everything:** Olist is a ~2-year dataset where the overwhelming majority of customers purchased exactly once. That single fact drove every method choice in this project. It's why a standard RFM segmentation had to be adapted, why cohort and CLV analysis wasn't possible here, and why delivery experience was the lever worth testing. The constraints here are deliberate, not gaps.

<!-- VISUAL SLOT: one clean chart here, the 96.88% one-and-done, or the delivery bound shown as a sliver against total non-return. To be added in final pass. -->

---

## The question

The intuitive explanation for why customers don't come back is a bad first experience, and the most measurable, most fixable version of "bad first experience" is a late delivery. If late first deliveries genuinely drive customers away, then improving delivery is a retention lever the business can actually pull.

So that became the testable question at the heart of this project: **does first-order delivery experience drive retention, and if so, how much is fixing it worth?**

The honest way to answer it wasn't to find a correlation and call delivery the cause. It was to measure how much of the problem delivery could actually explain.

## The data

- **Source:** [Olist Brazilian E-Commerce dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle), linked, not committed.
- **Scale:** 9 relational tables, ~100K orders, ~96K unique customers, R$15.8M revenue, Sept 2016 to Oct 2018.

## Approach

Built as a staged pipeline in pure PostgreSQL:

- **Bronze → silver ETL:** raw CSVs loaded into plain text tables first, then cleaned and typed in a second layer. Loading loose first kept the meaningful blanks (orders that never delivered) that a strict load would have thrown away.
- **Techniques:** CTEs, multi-table joins, and window functions (`LAG`, `NTILE`, running totals, moving averages) throughout.
- **Structure:** a three-act analysis: landscape (is this a healthy business?), then concentration (who carries it?), then retention diagnosis (why don't customers return, and can it be fixed?).

---

## Key findings

The analysis ran in three acts, each answering a question that set up the next.

**Act 1: the business is growing, but it leans on a few things.**
Revenue grew steadily to R$15.8M across the period. But it was concentrated from the start: **18 of 74 product categories generated 80% of revenue**, and the top 10% of sellers generated **67%**. A healthy-looking top line resting on a narrow base.

**Act 2: the narrow base includes the customers, and most of them never come back.**
The top 25% of customers by spend drove ~60% of revenue. And the headline fact of the whole dataset surfaced here: **96.88% of customers bought exactly once.** Repeat buyers were just ~3% of the base. This is where a standard RFM segmentation broke and had to be adapted (see *Judgment calls*).

**Act 3: the retention crisis is structural, not operational.**
This is the core of the project. If a bad first delivery drives customers away, delivery is a lever the business can pull, so I tested it:

- Late deliveries did get worse reviews (average review score fell from 4.32 for very-early deliveries to 3.78 for late ones), confirming delivery affects satisfaction. But the drop was mild, not catastrophic, and ~93% of orders actually arrived *early*, so late delivery is a rare exception, not the norm.
- Controlling for region, customers whose first delivery was late returned only slightly less often than those whose delivery was on time (a gap of roughly half a percentage point).
- **Sizing that gap is the headline: fixing every late delivery company-wide would recover about 40 customers, roughly 0.04% of everyone who didn't return.** Delivery, the most actionable lever available, explains almost none of the problem. The retention crisis isn't caused by logistics, which are already excellent. It's structural: this is a marketplace where customers simply don't repeat.

**The synthesis: even the best customers barely return.**
Return rate does rise with spend: the top spend tier returns at 7.78%, versus 0.28% for the bottom. But 7.78% still means ~92% of even the highest-value customers are one-and-done. So there's no loyal high-value base to rely on, only high-value *one-timers*. Whatever value a high-value customer represents is mostly realised on their first order, because most never place a second.

---

## Judgment calls

The findings above are only as good as the methodological choices behind them. This section explains the ones that mattered, including where I chose *not* to do something, or chose not to overclaim. This is where the real work lives.

### Adapting RFM instead of forcing it

RFM segmentation scores customers on three things: Recency (how recently they bought), Frequency (how often), and Monetary value (how much they spent). It only works if customers actually differ on all three axes.

On this data, two of the three collapsed. Frequency was the same value (one) for almost everyone, because 96.88% of customers bought exactly once; an axis where nearly everyone is identical can't separate anyone. Recency broke too, though more subtly: it's meant to measure whether a customer is still active or going cold, but that only means something for people with an ongoing relationship. For a customer who bought once and never returned, "recency" is just the date of that single purchase. It says nothing about engagement, because there's no pattern of behaviour to read. With two of the three axes carrying almost no information, a standard 5×5×5 RFM grid would have been meaningless: nearly every customer would collapse into the same cell.

So I adapted the method to what the data could actually support. I kept Monetary, since spend genuinely varied, and split customers into spend quartiles. I replaced Frequency with a simple repeat-flag (one purchase versus two or more) since the only meaningful distinction left was whether someone came back at all. And I dropped Recency as a segmentation axis, keeping it only as a caveat.

### Bounding the delivery effect instead of asserting it

Customers whose first delivery was late did return slightly less often than those whose delivery was on time. The easy move would be to stop there and announce that late delivery drives customers away. But a direction isn't a size. "Slightly less" could mean a lot or almost nothing, and the only way to know is to measure how much of the problem fixing delivery could actually solve.

So I sized it. Late first-delivery customers returned at 2.6%; on-time ones at 3.2%, a gap of 0.6 percentage points. If fixing delivery lifted the late group up to the on-time rate, each of the ~6,350 late customers would gain that 0.6-point better chance of returning:

```
6,350 late customers × 0.6 percentage points ≈ 40 recovered customers
```

Against the ~90,000 customers who never returned, those 40 are about **0.04% of the entire non-return problem.** And that's an upper bound: it assumes the whole gap is caused by delivery and that every late delivery could be perfectly fixed, so the real number is smaller.

That small number is the finding. Delivery is the most actionable lever available, since the platform can invest in logistics, yet it explains almost none of why customers don't come back. Olist's delivery is already excellent (about 93% of orders arrive early), and fixing the rare late ones would barely move retention. The crisis isn't operational. It's structural: this is a marketplace where customers simply don't repeat, and no single operational fix changes that.

### Controlling for region, and checking it was safe to

The delivery-vs-return comparison had an obvious trap: maybe late deliveries happen more in certain regions, and maybe those regions just have worse retention for unrelated reasons. If so, a raw "late vs on-time" comparison would really be measuring region, not delivery. The fix is to compare late vs on-time *within* each region, so region can't be the hidden explanation.

But controlling for something splits the data into smaller groups, and each group has to stay big enough to trust. So before committing, I checked the cell sizes. Controlling at the state level (27 states) left roughly a third of the groups with only a handful of late customers. Return rates built on single-digit samples are noise, not signal. So I grouped the 27 states into Brazil's 5 macro-regions, which kept every group well-populated while still controlling for geography. The choice of granularity came from testing the data, not from a default.

### Catching a revenue double-count before it spread

Revenue lives in the order-items table. Payments live in a separate table, and an order can have several of each. Joining orders to items *and* payments in one query, the natural first instinct, multiplies each item row by the number of payment rows, silently inflating revenue.

I caught this by validating the total two ways: the naive join gave R$16.57M, the correct single-grain calculation gave R$15.84M, a 4.6% overstatement from a join error, not a data error. The gap was small enough to pass unnoticed and large enough to distort every downstream revenue figure, so catching it early mattered. Every revenue number in this project is computed at the correct grain.

### Claim discipline: never saying more than the data supports

Every finding here is labelled by what it can actually claim. Concentration and growth numbers are *descriptions*, measured facts. The link between late delivery and lower return is an *association*, and once region is held fixed, an *association under control*. It is never written as "delivery causes churn," because a controlled comparison on observational data isn't proof of cause. Findings built on thin samples or narrow margins are flagged as such.

---

## What this means for the business

Put together, the findings describe a specific kind of fragility. The platform grows, but almost entirely by acquiring new customers, with no meaningful repeat base underneath the growth. Revenue leans on a narrow set of sellers and categories, and even the highest-value customers rarely come back. It's a leaky bucket: water goes in the top fast enough that the level rises, but the bucket doesn't hold.

That reframes where the leverage sits. The intuitive fix, improving delivery to win customers back, barely moves the number, because non-return isn't an operational failure. Since most high-value customers are captured only once, the first order is effectively the whole relationship. The first purchase, not the second, is where most of the value is won or lost.

## Limitations

This is a ~2-year dataset where ~97% of customers bought once, and the honest scope reflects that:

- **No cohort, churn, or CLV modelling.** These techniques need repeat behaviour and a longer time window to mean anything; on this data they would have been empty exercises.
- **The delivery finding is observational.** It's controlled for region, but not a randomised test, so the strongest claim is association, not proof of cause.
- **The late-delivery sample skews small** because Olist delivers early so often. The bound is built on the sizeable groups; the effect is honestly an upper estimate.

## Data quality handling

Most of the effort went into not being misled by the data. Beyond the revenue double-count above, the validation layer caught and handled: a customer-identity trap (`customer_id` is per-order, `customer_unique_id` is per-person, so using the wrong one fabricates a 0% retention rate); ~1M duplicate geolocation rows collapsed to ~19K; delivery-date NULLs preserved as meaningful (undelivered orders) rather than dropped; reviews written *before* delivery excluded from the delivery analysis; and a 676-customer discrepancy traced to itemless cancelled orders via staged row counts and an anti-join. Full detail is in the [traceability matrix](docs/traceability_matrix.md).

## Repository guide

- **`/sql`**: queries organised by act, each with a header noting the question it answers.
- **`/docs/traceability_matrix.md`**: every question mapped to its method, claim type, finding, and caveats.
- **Data**: the [Olist dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) is linked, not committed; only queries and outputs live here.

*Built in PostgreSQL.*
