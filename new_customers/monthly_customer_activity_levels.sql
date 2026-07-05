/*
This query builds off the customer usage concept and determines when an account crosses
the active customer threshold (chc_usage >= 100 in current month and chc_usage < 100 in
prev month) or the churned customer threshold (chc_usage < 100 in current month and 
chc_usage >= 100 in previous month). Some additional work is needed to get the monthly 
aggregates of active and churning customers, but this is the foundation to answer those 
quesitons.
*/

WITH DS AS (
  SELECT DISTINCT
    DATE_TRUNC('month', timestamp_hour) as month
  FROM
    date_spine
  ),

U AS (
  SELECT
    DATE_TRUNC('month', timestamp_hour) AS period,
    COALESCE(CASE WHEN account__id = '' THEN NULL ELSE account__id END, organization__id) as entity_id,
    SUM(toFloat64(organization__CHC_usage)) as total_chc_usage
  FROM
    default.demo_usage_data_9
  GROUP BY 1,2
  ),
  
UST AS (
  SELECT
    DS.month,
    U.entity_id,
    U.total_chc_usage,
    lagInFrame(U.total_chc_usage) OVER (PARTITION BY U.entity_id ORDER BY U.period ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as previous_total_chc_usage
  FROM
    DS
  LEFT JOIN
    U
    ON DS.month = U.period
  )
  
SELECT
  *,
  CASE WHEN total_chc_usage >= 100 THEN TRUE ELSE FALSE END AS is_curr_period_customer,
  CASE WHEN previous_total_chc_usage >= 100 THEN TRUE ELSE FALSE END AS is_prev_period_customer,
  CASE WHEN previous_total_chc_usage < 100 AND total_chc_usage >= 100 THEN TRUE ELSE FALSE END AS crossed_active_threshold_curr_period,
  CASE WHEN previous_total_chc_usage >= 100 AND total_chc_usage < 100 THEN TRUE ELSE FALSE END AS crossed_churn_threshold_curr_period,
  CASE WHEN previous_total_chc_usage < 100 AND total_chc_usage < 100 THEN TRUE ELSE FALSE END AS below_churn_threshold_two_conesq_periods,
  CASE WHEN two_previous_total_chc_usage < 100 AND previous_total_chc_usage < 100 AND total_chc_usage < 100 THEN TRUE ELSE FALSE END AS below_churn_threshold_three_conesq_periods,
  MIN(CASE WHEN total_chc_usage >= 100 THEN month END) OVER (PARTITION BY entity_id) AS first_customer_month,
  MAX(CASE WHEN total_chc_usage >= 100 THEN month END) OVER (PARTITION BY entity_id) AS last_customer_month
FROM
  UST
ORDER BY 2 ASC, 1 ASC