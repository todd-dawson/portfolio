/*
This query adds some simple billing state filtering to differentiate between expected
revenue and probable unbilled usage with a simple price sheet added to convert CHCs for 
different SKUs into non-discounted $USD for some basic monthly and annual run rate 
determinations. These numbers are mainly directional but will probably be within +-15% of
actuals
*/ 

WITH PU AS (
  SELECT
    DATE_TRUNC('month', timestamp_hour) AS period,
    organization__billing_status AS org_level_billing_status,
    CASE WHEN organization__billing_status IN ('EMPLOYEE', 'PAID', 'PREPAID', '', 'NO_BILLING', 'REVIEW_MANUALLY') THEN TRUE ELSE FALSE END AS is_revenue,
    SUM(toFloat64(organization__CHC_usage)) AS total_chc_usage,
    SUM(toFloat64(organization__chc_usage_compute)) AS total_compute_chc,
    SUM(toFloat64(organization__chc_usage_storage)) AS total_storage_chc,
    SUM(toFloat64(organization__chc_usage_backup)) AS total_backup_chc,
    SUM(toFloat64(organization__chc_usage_datatransfer)) as total_data_transfer_chc
  FROM
    usage_history
  GROUP BY 1, 2, 3
  ),
RR AS (
  SELECT
    period,
    SUM(CASE WHEN is_revenue = TRUE THEN total_compute_chc * 1.0 ELSE 0 END) AS total_compute_dollar_usage,
    SUM(CASE WHEN is_revenue = TRUE THEN total_storage_chc * 0.4 ELSE 0 END) AS total_storage_dollar_usage,
    SUM(CASE WHEN is_revenue = TRUE THEN total_backup_chc * 0.1 ELSE 0 END) AS total_backup_dollar_usage,
    SUM(CASE WHEN is_revenue = TRUE THEN total_data_transfer_chc * 0.6 ELSE 0 END) AS total_data_transfer_dollar_usage,
    total_compute_dollar_usage + total_storage_dollar_usage + total_backup_dollar_usage + total_data_transfer_dollar_usage as monthly_run_rate
  FROM
    PU
  GROUP BY 1
  )
  
SELECT
  period,
  monthly_run_rate AS mrr,
  monthly_run_rate * 12.0 AS simple_arr_forecast,
  AVG(monthly_run_rate) OVER (ORDER BY period ASC ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) * 12.0 as avg_l90_arr_forecast,
  SUM(monthly_run_rate) OVER (ORDER BY period ASC ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS trailing_12_month_total
FROM
  RR
ORDER BY 1 ASC