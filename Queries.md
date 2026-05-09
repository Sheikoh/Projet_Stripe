# Q1 Revenue by merchant tier (snowflake)

SELECT
  d.year,
  d.month,
  m.tier,
  g.country_code,                              -- was g.country (field renamed in final schema)
  SUM(f.amount_usd)             AS gross_revenue,
  SUM(f.amount_usd) FILTER (WHERE f.status = 'refunded') AS refunds,
  COUNT(DISTINCT f.merchant_id) AS active_merchants,
  COUNT(*)                      AS txn_count,
  ROUND(100.0 * SUM(CASE WHEN f.status='refunded' THEN 1 ELSE 0 END)
        / COUNT(*), 2)          AS refund_rate_pct
FROM   fact_transactions   f
JOIN   dim_date            d  ON d.date_id     = f.date_id
JOIN   dim_merchants       m  ON m.merchant_id = f.merchant_id  -- was dim_merchant (singular)
  AND  m.is_current = true                     -- required: SCD Type-2 filter
JOIN   dim_geography       g  ON g.geo_id      = f.geo_id
WHERE  d.year = 2026
GROUP  BY 1,2,3,4
ORDER  BY 1,2,3;

# Q2 Real-time fraud queue (PostgreSQL)

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT
  t.transaction_id,
  t.merchant_id,
  t.amount,
  t.currency,
  t.fraud_score,
  ip_c.country_code  AS ip_country,
  cust_c.country_code AS customer_country,
  t.device_type,
  t.version
FROM   transactions  t
JOIN   customers     c       ON c.customer_id  = t.customer_id  -- was c.id (wrong PK name)
JOIN   countries     ip_c   ON ip_c.country_id = t.ip_country_id
JOIN   countries     cust_c ON cust_c.country_id = c.country_id -- resolves FK to code for comparison
WHERE  t.fraud_score > 0.60
  AND  t.status      = 'pending'
  AND  t.created_at  > now() - interval '1 hour'
  AND  t.ip_country_id != c.country_id         -- compare integer FKs directly (both ref countries)
ORDER  BY t.fraud_score DESC
LIMIT  100;

COMMIT;

# Q3 RFM customer segmentation (Snowflake)

WITH rfm AS (
  SELECT
    f.customer_id,
    DATEDIFF('day', MAX(d.full_date), CURRENT_DATE) AS recency,
    COUNT(*)                                         AS frequency,
    SUM(f.amount_usd)                                AS monetary
  FROM   fact_transactions f
  JOIN   dim_date          d ON d.date_id = f.date_id
  WHERE  f.status    = 'succeeded'
    AND  d.full_date >= DATEADD('month', -12, CURRENT_DATE)
  GROUP  BY 1
),
scored AS (
  SELECT *,
    NTILE(5) OVER (ORDER BY recency   DESC) AS r,
    NTILE(5) OVER (ORDER BY frequency ASC)  AS f,
    NTILE(5) OVER (ORDER BY monetary  ASC)  AS m
  FROM rfm
)
SELECT *,
  CASE
    WHEN r >= 4 AND f >= 4 THEN 'Champions'
    WHEN r >= 3 AND f >= 3 THEN 'Loyal'
    WHEN r >= 4 AND f <= 2 THEN 'New customers'
    WHEN r <= 2 AND f >= 3 THEN 'At risk'
    ELSE 'Hibernating'
  END AS segment
FROM scored;

# Q4 Rolling 7-days revenue (Snowflake)

SELECT
  merchant_id,
  date_id,
  full_date,
  gross_revenue                                    AS daily_revenue,
  SUM(gross_revenue) OVER (
    PARTITION BY merchant_id
    ORDER BY date_id
    ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
  )                                                AS rolling_7d_revenue,
  ROUND(100.0 * (gross_revenue -
    LAG(gross_revenue, 7) OVER (PARTITION BY merchant_id ORDER BY date_id))
    / NULLIF(LAG(gross_revenue, 7) OVER (PARTITION BY merchant_id ORDER BY date_id), 0)
  , 2)                                             AS wow_growth_pct
FROM   mv_daily_revenue                            -- was fact_transactions (wrong layer)
WHERE  year = 2026
ORDER  BY merchant_id, date_id;

# Q5 Audit history for a transaction (MongoDB)

db.audit_log.find({
  "entity.type": "transaction",
  "entity.id":   "txn_01J2K..."
}).sort({ ts: 1 })

// Returns full before/after snapshots in version order.
// Works correctly even after GDPR erasure of the customer —
// all fields are embedded, no dangling references.

# Q6 Checkout funnel analysis (MongoDB)

db.user_sessions.aggregate([
  { $match: {
      started_at: { $gte: ISODate("2026-05-01") },
      bucket: 1                                    // query root buckets only
  }},
  { $unwind: "$events" },
  { $group: {
      _id:             "$events.type",
      count:           { $sum: 1 },
      unique_sessions: { $addToSet: "$_id" }
  }},
  { $addFields: {
      unique_count: { $size: "$unique_sessions" }
  }},
  { $project: {
      _id: 1, count: 1, unique_count: 1
  }},
  { $sort: { count: -1 }}
])