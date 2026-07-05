/*
This builds on the customer_activity_levels query and determines net new customers,
current customers, soft churning customers, and fully churned customers.
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
    usage_history
  GROUP BY 1,2
  ),
  
UST AS (
  SELECT
    DS.month,
    U.entity_id,
    U.total_chc_usage,
    lagInFrame(U.total_chc_usage) OVER (PARTITION BY U.entity_id ORDER BY U.period ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as previous_total_chc_usage,
    lagInFrame(U.total_chc_usage, 2) OVER (PARTITION BY U.entity_id ORDER BY U.period ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as two_previous_total_chc_usage
  FROM
    DS
  LEFT JOIN
    U
    ON DS.month = U.period
  ),

 USTC AS (
  SELECT
    *,
    CASE WHEN total_chc_usage >= 1 THEN TRUE ELSE FALSE END AS is_curr_period_customer,
    CASE WHEN previous_total_chc_usage >= 1 THEN TRUE ELSE FALSE END AS is_prev_period_customer,
    CASE WHEN previous_total_chc_usage < 1 AND total_chc_usage >= 1 THEN TRUE ELSE FALSE END AS crossed_active_threshold_curr_period,
    CASE WHEN previous_total_chc_usage >= 1 AND total_chc_usage < 1 THEN TRUE ELSE FALSE END AS crossed_churn_threshold_curr_period,
    CASE WHEN previous_total_chc_usage < 1 AND total_chc_usage < 1 THEN TRUE ELSE FALSE END AS below_churn_threshold_two_conesq_periods,
    CASE WHEN two_previous_total_chc_usage < 1 AND previous_total_chc_usage < 1 AND total_chc_usage < 1 THEN TRUE ELSE FALSE END AS below_churn_threshold_three_conesq_periods,
    MIN(CASE WHEN total_chc_usage >= 1 THEN month END) OVER (PARTITION BY entity_id) AS first_customer_month,
    MAX(CASE WHEN total_chc_usage >= 1 THEN month END) OVER (PARTITION BY entity_id) AS last_customer_month
  FROM
    UST
  ),

FINAL AS (  
  SELECT
    *,
    CASE WHEN first_customer_month = month THEN TRUE ELSE FALSE END AS is_customer_acq_period,
    CASE WHEN last_customer_month + INTERVAL 1 MONTH = month THEN TRUE ELSE FALSE END AS is_customer_churn_period,
    CASE WHEN crossed_churn_threshold_curr_period = TRUE AND last_customer_month + INTERVAL 1 MONTH != month THEN TRUE ELSE FALSE END AS is_customer_soft_churn_period
  FROM
    USTC
  )
  
  SELECT
    month, 
    COUNT(DISTINCT CASE WHEN is_curr_period_customer = TRUE THEN entity_id END) as active_customers,
    COUNT(DISTINCT CASE WHEN is_customer_acq_period = TRUE THEN entity_id END) AS net_new_customers,
    COUNT(DISTINCT CASE WHEN is_customer_churn_period = TRUE THEN entity_id END) AS churning_customers,
    COUNT(DISTINCT CASE WHEN is_customer_soft_churn_period = TRUE THEN entity_id END) AS soft_churning_customers
  FROM
    FINAL
  GROUP BY 1
  ORDER BY 1 ASC