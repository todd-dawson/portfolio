/*
This query was used to generate CSV exports that were eventually pulled into an accounting
spreadsheet that manually tracked a yet-to-be productized use case of the UserTesting 
platform for quantitative survey testing. This SKU was piloted by a small number of high
value customers before the feature was developed into the platform fully. Eventually the
method of turning raw credit payments into consumable usage credits would form the basis
of PAYG and overage payments for the usage-based revenue model that UT would roll out.
*/

WITH I as (
  SELECT
    order_id,
    SUM(credit_total) as credit_total,
    SUM(dollar_total) as dollar_total
  FROM
    mysql_usertesting_orders_production.invoices
  GROUP BY 1
  ),
  
PP as (
    SELECT
      PP.type,
      PP.state,
      SUM(PP.prepaid_credit_value_spent) as prepaid_credit_value_spent,
      SUM(PP.live_conversation_minutes_value_spent) as live_conversation_minutes_value_spent
    FROM
      mysql_usertesting_orders_production.payments as PP
    LEFT JOIN
      mysql_usertesting_orders_production.sessions as S
      ON PP.session_id = S.id
    WHERE
      S.account_id = 662545 -- specific account that doing quant testing
    GROUP BY 1, 2
 ),
 
P as (
    SELECT DISTINCT
      O.id as order_id,
      P.prepaid_credit_id,
      SUM(P.prepaid_credit_value_spent) as prepaid_credit_value_spent
    FROM 
      mysql_usertesting_orders_production.studies as S
    INNER JOIN 
      mysql_usertesting_orders_production.line_items as LI
    ON LI.product_id = S.id AND LI.product_type = 'Study' 
    INNER JOIN 
      mysql_usertesting_orders_production.orders as O 
      ON O.id = LI.order_id 
    INNER JOIN 
      mysql_usertesting_orders_production.payments as P 
      ON P.order_id = O.id AND P.type IN ('PrepaidCreditPayment')
    WHERE 
      S.account_id = 662545 -- specific account that doing quant testing
      AND O.state = 'completed' 
      AND O.created_at >= '2019-01-17' -- date quant testing was allowed, which pre dates the 2019-02-02 subscription start date
    GROUP BY 1, 2
  ),
  
C as (
  SELECT DISTINCT
    P.order_id,
    P.prepaid_credit_value_spent,
    (CC.expiration_date:date) as expiration_date
  FROM
    P
  LEFT JOIN
    mysql_usertesting_orders_production.credits as CC
  ON P.prepaid_credit_id = CC.id
  WHERE
    CC.credit_type NOT IN ('refund')
    OR CC.credit_type IS NULL
  )

SELECT DISTINCT
  O.completed_at:month as order_completion_month,
  U2.email as orderer_email,
  SUM(O.credit_total) as credits_used,
  SUM(I.credit_total) as invoiced_credits
FROM
  mysql_usertesting_orders_production.orders as O
LEFT JOIN
  derived.account_table as AT
  ON O.account_id = AT.account_id
LEFT JOIN
  mysql_usertesting_orders_production.accounts as A
  ON AT.account_id = A.id
LEFT JOIN
  mysql_usertesting_orders_production.users as U
  ON A.owner_id = U.id
LEFT JOIN
  mysql_usertesting_orders_production.users as U2
  ON O.user_id = U2.id
LEFT JOIN
  I
  ON O.id = I.order_id
LEFT JOIN
  C
  ON O.id = C.order_id
WHERE
  U.email ILIKE '%@quanttesting.com%'
  AND O.state = 'completed'
  AND O.created_at >= '2019-01-17' -- date quant testing was allowed, which pre dates the 2019-02-02 subscription start date
  AND O.type = 'UserTestOrder'
GROUP BY 1,2
ORDER BY 1 ASC