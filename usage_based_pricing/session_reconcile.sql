/*
This query handles several historical data issues in the event ledger to allow for a clean
session table. The most recent session state for a concluded session is selected due to
fact that sessions had the chance to reawaken under certain edge cases (participant number
being increased after session launch, for example). Intermediate session states are also
represented but the state is set to NULL in order to reduce confusion with transient state
names.

The main purpose of this table was to serve as a basis to determine what credits were in a
consumed state (event_name = 'SESSION_CONCLUDED' with a state = 'COMPLETED') vs those
in-flight (event_name = 'SESSION_LAUNCHED' where no corresponding event_name = 
'SESSION_CONCLUDED' exists) vs those automatically refunded to the pool (event_name =
'SESSION_CONCLUDED' and a state = 'FAILED') vs those available for a relaunch (
event_name = 'SESSION_CONCULDED' and state = 'CANCELED'). The different states of credits
were then used to determine the service delivery state for ASC 606 revenue recognition 
accounting in both committed spend and Pay As You Go subscription models.
*/

WITH SUBS AS (
  SELECT DISTINCT
    subscription_uuid
  FROM
    ledger.ledger_events
  WHERE
    event_name = 'ACCOUNT_PROVISIONED'
    AND published_at >= '2020-09-18'
  ),
  
MPA AS (
  SELECT DISTINCT
    LE.session_uuid,
    MAX(LE.published_at) AS max_published_at
  FROM
    ledger.ledger_events AS LE
  JOIN
    SUBS
    ON LE.subscription_uuid = SUBS.subscription_uuid
  WHERE
    LE.event_name = 'SESSION_CONCLUDED'
  GROUP BY 1
  ),
  
MSC AS (
  SELECT DISTINCT
    LE.event_uuid,
    LE.published_at,
    LE.subscription_uuid,
    LE.workspace_uuid,
    LE.session_uuid,
    LE.participant_uuid,
    LE.panel_type,
    LE.event_name,
    LE.point_cost_for_event,
    LE.point_hold_for_event,
    LE.session_type,
    LE.session_duration,
    LE.session_status,
    CASE WHEN SS.state = 'completed' THEN 'COMPLETED'
         WHEN SS.state = 'problem' THEN 'FAILED'
         WHEN SS.state IN ('expired', 'canceled') THEN 'CANCELED'
         END AS current_session_state
  FROM
    ledger.ledger_events AS LE
  JOIN
    SUBS
    ON LE.subscription_uuid = SUBS.subscription_uuid
  JOIN
    MPA
    ON LE.session_uuid = MPA.session_uuid AND LE.published_at = MPA.max_published_at
  LEFT JOIN
    mysql_usertesting_orders_production.sessions as SS
    ON MPA.session_uuid = SS.uid AND SS._fivetran_deleted = 'f'
  WHERE
    LE.event_name = 'SESSION_CONCLUDED'
  ),
  
OLE AS (
  SELECT DISTINCT
    LE.event_uuid,
    LE.published_at,
    LE.subscription_uuid,
    LE.workspace_uuid,
    LE.session_uuid,
    NULL AS participant_uuid,
    CASE WHEN LE.event_name = 'SESSION_LAUNCHED' THEN LE.panel_type
         ELSE NULL
         END AS panel_type,
    LE.event_name,
    LE.point_cost_for_event,
    LE.point_hold_for_event,
    LE.session_type,
    LE.session_duration,
    LE.session_status,
    NULL as current_session_state
  FROM
    ledger.ledger_events as LE
  JOIN
    SUBS
    ON LE.subscription_uuid = SUBS.subscription_uuid
  WHERE
    LE.event_name NOT IN ('SESSION_CONCLUDED', 'ACCOUNT_PROVISIONED', 'GRANT_POINTS')
  )

SELECT
  *
FROM
  MSC

UNION

SELECT
  *
FROM
  OLE
ORDER BY 5 ASC, 2 ASC