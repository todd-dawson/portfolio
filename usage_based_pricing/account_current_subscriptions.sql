/*
This query uses the usage ledger to determine the most recent active subscription for an
account and pulls some dims into that context based on thier CURRENT values in SFDC. For
historically accurate details a dimensional history model needs to be built, but since
all of the subscriptions present in the ledger are less than 6 months old, that is a
future consideration.

The main purpose of this output was to handle the tracking of stub deal top ups during an
annual subscription cycle as UserTesting moved into usage-based pricing. Some customers 
burned credits much faster than expected, and since the alpha version of usage was 
manually tracked in reporting by teh account teams, it was important to surface the most
recent active subscripotion and the subsequent credits remaining on a daily basis.
Ultimately this became a dbt model and view in the data warehouse that was referenced for
its dimensions.
*/

WITH CURR_SUB AS (
  SELECT 
    LE.account_uuid,
    LE.subscription_uuid,
    A.id AS ut_account_id,
    A.name AS ut_account_name,
    SUB.id AS subscription_id,
    SUB.plan AS subscription_plan_name,
    SUB.point_based,
    SUB.start_at AS subscription_start_date,
    SUB.end_at AS subscription_end_date,
    SFA.name AS salesforce_name,
    SFA.id AS sfdc_id,
    SFPA.name AS parent_name,
    SFPA.id AS sfdc_parent_id,
    AE.name AS account_executive,
    CSM.name AS customer_success_manager,
    RM.name AS renewal_manager,
    SFA.segment_assignment_c AS segment_assignment,
    SFA.region_c AS region,
    C.name AS main_point_of_contact,
    C.email AS main_point_of_contact_email,
    SUB.session_units,
    LE.points_available,
    (LE.points_available + LE.point_cost) AS session_units_purchased, -- total SUs for subscription duration as a checksum for proper inner joins
    SUB.sfdc_subscription_id,
    A.sfdc_instance_id,
    RANK() OVER (PARTITION BY LE.account_uuid ORDER BY LE.published_at DESC, LE.point_hold DESC, LE.event_uuid DESC) AS sub_rank
  FROM 
    ledger.ledger_events AS LE
  JOIN 
    mysql_usertesting_orders_production.accounts AS A 
    ON A.uid = LE.account_uuid
  LEFT JOIN 
    mysql_usertesting_orders_production.subscriptions AS SUB 
    ON SUB.uuid = LE.subscription_uuid
  LEFT JOIN
    salesforce.account AS SFA 
    ON SFA.user_testing_com_account_id_c = A.id AND SFA.is_deleted IS FALSE
  LEFT JOIN 
    salesforce.account AS SFPA 
    ON LEFT(SFPA.id, 15) = NVL(LEFT(SFA.ultimate_parent_id_c, 15), LEFT(A.id, 15)) AND SFPA.is_deleted IS FALSE -- handles custom SFDC parent account hierarchy mapping
  LEFT JOIN 
    salesforce."user" AS AE 
    ON SFA.owner_id = AE.id
  LEFT JOIN 
    salesforce."user" AS CSM
    ON SFA.csm_c = CSM.id
  LEFT JOIN 
    salesforce."user" AS RM 
    ON SFA.renewal_manager_c = RM.id
  LEFT JOIN 
    salesforce.contact AS C 
    ON SFA.main_point_of_contact_c = C.id
  WHERE 
    LE.event_type  in ('ACCOUNT_PROVISIONED', 'SESSION_LAUNCHED')
  )
  
SELECT 
  account_uuid as account_guid,
  subscription_uuid as subscription_guid,
  * EXCLUDE (account_uuid, subscription_uuid)
FROM 
  CURR_SUB
WHERE 
  sub_rank = 1