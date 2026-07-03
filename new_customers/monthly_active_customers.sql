/*
This query builds off the customer usage concept and produces a running count of active
custoemr accounts.
*/

WITH DS AS (
  SELECT DISTINCT
    DATE_TRUNC('month', timestamp_hour) as month
  FROM
    date_spine
  ),

THRESH AS (
  SELECT
    DATE_TRUNC('month', timestamp_hour) AS period,
    COALESCE(CASE WHEN account__id = '' THEN NULL ELSE account__id END, organization__id) as entity_id,
    SUM(toFloat64(organization__CHC_usage)) as total_chc_usage
  FROM
    usage_history
  GROUP BY 1,2
  HAVING
    total_chc_usage >= 100
  )

SELECT
  DS.month,
  COUNT(DISTINCT entity_id) as active_customers
FROM
  DS
LEFT JOIN
  THRESH
  ON DS.month = THRESH.period
GROUP BY 1
ORDER BY 1 ASC