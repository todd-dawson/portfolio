/*
This table determines the fist period that a given parent account reaches the usage 
threshold of being considered a customer (100 CHC consumed in a calendar month). This also
marks a shift from determining this threshold at the organization level (orgs roll up to 
accounts), since accounts are the business entities with whom we do business.

From this table joins to dimensional hstories can be made for answering questions related 
to the growthy of the customer base across such dimensions.
*/

WITH THRESH AS (
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
  entity_id,
  MIN(period) AS first_customer_period
FROM
  THRESH
GROUP BY 1
