/////////////////////////////////////////////////////////
// Stripe BUSINESS CASE - OLTP & OLAP MODEL (DBML/dbdiagram)
/////////////////////////////////////////////////////////

// ---------- OLTP SECTION ----------
Table merchants {
  merchant_id uuid [pk, note: "ULID-based canonical ID"]
  name varchar(255) [not null]
  country_id int [ref: > countries.country_id]
  tier varchar(20) [note: "starter | growth | enterprise"]
  created_at timestamp
  updated_at timestamp
}

Table customers {
  customer_id uuid [pk]
  merchant_id uuid [not null, ref: > merchants.merchant_id]
  email varchar(255)
  country_id int [ref: > countries.country_id]
  created_at timestamp
}

Table payment_methods {
  payment_method_id uuid [pk]
  customer_id uuid [ref: > customers.customer_id]
  type varchar(20) [note: "card | bank | wallet"]
  last4 char(4)
  brand varchar(50)
  fingerprint varchar(255) [unique, note: "used for deduplication"]
  created_at timestamp
}

Table transactions {
  transaction_id uuid [pk]
  merchant_id uuid [not null, ref: > merchants.merchant_id]
  customer_id uuid [ref: > customers.customer_id]
  payment_method_id uuid [ref: > payment_methods.payment_method_id]
  amount bigint [not null, note: "stored in cents, never float"]
  currency char(3) [not null]
  status varchar(20) [note: "pending | succeeded | failed | refunded"]
  ip_country_id int [ref: > countries.country_id]
  device_type varchar(50)
  fraud_score decimal(5,4)
  created_at timestamp
  updated_at timestamp
}

Table refunds {
  refund_id uuid [pk]
  transaction_id uuid [not null, ref: > transactions.transaction_id]
  amount bigint [not null]
  reason varchar(255)
  status varchar(20)
  created_at timestamp
}

Table countries {
  country_id int [pk, increment]
  country_name varchar(100)
  country_code char(2) [unique]
  currency_code char(3)
}

Table outbox_events {
  event_id uuid [pk]
  aggregate_id uuid [not null, note: "canonical ID of the changed entity"]
  event_type varchar(100) [note: "e.g. transaction.succeeded"]
  payload jsonb
  published boolean [default: false]
  created_at timestamp
}

// ---------- OLAP SECTION ----------
Table fact_transactions {
  transaction_id varchar [pk, note: "same canonical UUID as OLTP"]
  merchant_id varchar [ref: > dim_merchants.merchant_id]
  customer_id varchar [ref: > dim_customers.customer_id]
  payment_method_id varchar [ref: > dim_payment_methods.payment_method_id]
  date_id int [ref: > dim_date.date_id]
  geo_id int [ref: > dim_geography.geo_id]
  amount_usd decimal(18,4)
  original_amount bigint
  original_currency char(3)
  status varchar(20)
  fraud_score decimal(5,4)
  is_refunded boolean
  loaded_at timestamp
}

Table dim_merchants {
  merchant_id varchar [pk]
  name varchar(255)
  tier varchar(20)
  country_code char(2)
  valid_from date [note: "SCD Type-2 start"]
  valid_to date [note: "SCD Type-2 end — null means current"]
  is_current boolean
}

Table dim_customers {
  customer_id varchar [pk]
  segment varchar(50) [note: "champions | loyal | at_risk | hibernating"]
  ltv_usd decimal(18,4)
  country_code char(2)
  valid_from date [note: "SCD Type-2 start"]
  valid_to date [note: "SCD Type-2 end — null means current"]
  is_current boolean
}

Table dim_payment_methods {
  payment_method_id varchar [pk]
  type varchar(20)
  brand varchar(50)
  wallet_name varchar(50)
}

Table dim_date {
  date_id int [pk, increment]
  full_date date
  day_of_week int
  week int
  month int
  quarter int
  year int
  is_weekend boolean
  is_holiday boolean
}

Table dim_geography {
  geo_id int [pk, increment]
  country_code char(2)
  country_name varchar(100)
  region varchar(100)
  continent varchar(50)
}

Table mv_daily_revenue {
  date_id int [ref: > dim_date.date_id]
  merchant_id varchar [ref: > dim_merchants.merchant_id]
  tier varchar(20)
  country_code char(2)
  gross_revenue decimal(18,4)
  net_revenue decimal(18,4)
  refund_amount decimal(18,4)
  txn_count int
  avg_fraud_score decimal(5,4)
  note: "Materialized view — refreshed every 15 min by Airflow"
}