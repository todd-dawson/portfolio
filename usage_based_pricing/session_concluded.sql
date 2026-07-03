WITH VID as (
  SELECT
    *,
    FLOOR(duration % 60) as video_seconds,
    FLOOR(duration / 60) as video_minutes_total,
    video_minutes_total % 60 as video_minutes,
    FLOOR(video_minutes_total / 60) as video_hours,
    CASE WHEN video_hours > 0 THEN video_hours || 'h' || video_minutes || 'm' || video_seconds || 's'
         WHEN video_hours <= 0 AND video_minutes > 0 THEN video_minutes || 'm' || video_seconds || 's'
         ELSE video_seconds || 's'
         END as video_length,
    (FLOOR(duration / 60.0)) || 'm' || ROUND(((duration / 60.0)::decimal(7,2) - (FLOOR(duration / 60.0))) * 60) || 's' as video_duration,
    duration as video_duration_sec,
    MAX(created_at) OVER (PARTITION BY session_id) as max_created_at
  FROM
    mysql_usertesting_orders_production.videos
  WHERE
    _fivetran_deleted = 'f'
  ),
MLSR as (
  SELECT DISTINCT
    session_uuid,
    published_at,
    event_uuid,
    event_name,
    point_cost_for_event,
    point_hold_for_event,
    session_status,
    current_session_state,
    CASE WHEN event_name = 'SESSION_LAUNCHED' THEN 1
         WHEN event_name = 'SESSION_CONCLUDED' THEN 2
         WHEN event_name = 'SESSION_REFUND' THEN 3
         END as current_session_sequence_step,
    MAX(current_session_sequence_step) OVER (PARTITION BY session_uuid) as max_current_session_sequence_step,
    CASE WHEN max_current_session_sequence_step = 1 THEN 'LAUNCHED'
         WHEN max_current_session_sequence_step = 3 THEN 'REFUNDED'
         ELSE MAX(current_session_state) OVER (PARTITION BY session_uuid)
         END as max_current_session_state,
    MAX(published_at) OVER (PARTITION BY session_uuid) as max_published_at,
    SUM(point_cost_for_event) OVER (PARTITION BY session_uuid) as reconciled_point_cost_for_event,
    SUM(point_hold_for_event) OVER (PARTITION BY session_uuid) as reconciled_point_hold_for_event,
    SUM(CASE WHEN event_name = 'SESSION_REFUND' THEN point_cost_for_event ELSE NULL END) OVER (PARTITION BY session_uuid) as total_refunded_points_for_event,
    MAX(CASE WHEN event_name = 'SESSION_CONCLUDED' THEN published_at ELSE NULL END) OVER (PARTITION BY session_uuid) as session_concluded_at,
    MAX(CASE WHEN event_name = 'SESSION_LAUNCHED' THEN published_at ELSE NULL END) OVER (PARTITION BY session_uuid) as session_launched_at,
    MAX(CASE WHEN event_name = 'SESSION_REFUND' THEN published_at ELSE NULL END) OVER (PARTITION BY session_uuid) as session_refunded_at,
    MAX(participant_uuid) OVER (PARTITION BY session_uuid) as final_participant_uuid,
    MAX(panel_type) OVER (PARTITION BY session_uuid) as panel_type,
    session_type,
    session_duration,
    MAX(CASE WHEN current_session_sequence_step = 1 THEN session_duration ELSE NULL END) OVER (PARTITION BY session_uuid) as scheduled_session_duration,
    MAX(CASE WHEN current_session_sequence_step = 2 THEN session_duration ELSE NULL END) OVER (PARTITION BY session_uuid) as actual_session_duration
  FROM
    ledger.session_reconcile
  ORDER BY 1 ASC, 2 ASC
  ),
SCH as (
  SELECT
    id,
    study_id,
    duration,
    RANK() OVER (PARTITION BY study_id ORDER BY id DESC) as rank
  FROM
    mysql_usertesting_orders_production.schedules 
  WHERE
    _fivetran_deleted = 'false'
  )

SELECT
  MLSR.session_concluded_at,
  LE.published_at,
  LE.event_uuid,
  LE.account_uuid,
  LE.subscription_uuid,
  LE.points_available,
  LE.point_cost, --as ledger_total_points_consumed_current_subscription, --needs better terminology
  LE.point_hold, --as ledger_total_points_hold_current_subscription --needs better terminology
  LE.point_cost_for_event,
  LE.point_hold_for_event as point_hold_cost_for_event,
  LE.session_uuid,
  LE.study_uuid,
  UO.uid as orderer_uuid,
  UC.uid as creator_uuid,
  MLSR.final_participant_uuid,
  CASE WHEN MLSR.panel_type = 'INTERNAL_PANEL' THEN 'OUR_PANEL'
       ELSE MLSR.panel_type
  	   END as panel_type,
  MLSR.session_type,
  LE.session_duration as duration, --need better solution for actual session duration
  VID.video_length,
  VID.video_duration_sec as video_length_sec,
  LE.workspace_uuid,
  MLSR.max_current_session_state as session_state,
  LE.event_type as event,
  S.id as session_id,
  S.reference_id as session_reference_id,
  S.state as orders_session_state,
  ST.id as study_id,
  ST.title as study_title,
  ST.form_used as type_of_test,
  CASE WHEN ST.product_type = 0 THEN 'Insight Core'
       WHEN ST.product_type = 1 THEN  'Product Insight'
       WHEN ST.product_type = 2 THEN  'Marketing Insight'
       ELSE 'Other'
       END as product,
  CASE WHEN SCH.duration > 0 THEN SCH.duration || ' Minutes'
       ELSE NULL
       END as scheduled_live_conversation_minutes,
  MLSR.session_launched_at,
  (((UO.first_name)::text || ' '::text) || (UO.last_name)::text)as orderer_name,
  UO.email as orderer_email,
  (((UC.first_name)::text || ' '::text) || (UC.last_name)::text) as creator_name,
  UC.email as creator_email,
  A.id as ut_account_id,
  A.name as ut_account_name,
  T.id as workspace_id,
  T.name as workspace_name,
  SUB.id as subscription_id,
  SUB.plan as subscription_plan_name,
  SFA.name as salesforce_name,
  SFA.id as sfdc_id,
  SFPA.name as parent_name,
  SFPA.id as sfdc_parent_id,
  MLSR.reconciled_point_cost_for_event,
  MLSR.reconciled_point_hold_for_event,
  MLSR.total_refunded_points_for_event,
  CASE WHEN MLSR.session_launched_at IS NULL AND MLSR.reconciled_point_cost_for_event < 0 THEN NULL
       ELSE MLSR.reconciled_point_cost_for_event
       END as adj_reconciled_point_cost_for_event,
  CASE WHEN MLSR.session_launched_at IS NULL THEN NULL
       ELSE MLSR.reconciled_point_hold_for_event
       END as adj_reconciled_point_hold_for_event,
  MLSR.session_refunded_at,
  MLSR.total_refunded_points_for_event as point_cost_for_refund,
  CASE WHEN ST.id IS NOT NULL THEN TRUE
       ELSE FALSE
       END as study_present_in_orders_yet,
  GETDATE() as dw_created_at
FROM
  ledger.ledger_events as LE
JOIN
  MLSR
ON LE.event_uuid = MLSR.event_uuid AND MLSR.current_session_sequence_step = MLSR.max_current_session_sequence_step
LEFT JOIN 
  mysql_usertesting_orders_production.sessions as S 
ON LE.session_uuid = S.uid AND S._fivetran_deleted = 'f'
LEFT JOIN
  mysql_usertesting_orders_production.studies as ST
ON LE.study_uuid = ST.sharing_id AND ST._fivetran_deleted = 'f'
LEFT JOIN 
  mysql_usertesting_orders_production.users as UO 
ON NVL(ST.ordered_by, ST.creator_id) = UO.id AND UO._fivetran_deleted = 'f'
LEFT JOIN 
  mysql_usertesting_orders_production.users as UC
ON ST.creator_id = UC.id AND UC._fivetran_deleted = 'f'
LEFT JOIN 
  mysql_usertesting_orders_production.accounts as A
ON LE.account_uuid = A.uid AND A._fivetran_deleted = 'f'
LEFT JOIN 
  mysql_usertesting_orders_production.teams as T 
ON LE.workspace_uuid = T.guid
LEFT JOIN
  mysql_usertesting_orders_production.subscriptions as SUB 
ON LE.subscription_uuid = SUB.uuid
LEFT JOIN 
  salesforce.account as SFA 
ON A.id = SFA.user_testing_com_account_id_c AND SFA.is_deleted IS FALSE
LEFT JOIN 
  salesforce.account as SFPA 
ON NVL(LEFT(SFA.ultimate_parent_id_c, 15), LEFT((TRIM('<a href="https://usertesting.my.salesforce.com/' FROM SFA.ultimate_parent_c)),15)) = LEFT(SFPA.id, 15) AND SFPA.is_deleted IS FALSE
LEFT JOIN
  SCH
ON ST.id = SCH.study_id AND SCH.rank = 1
LEFT JOIN
  VID
ON S.id = VID.session_id AND VID.created_at = VID.max_created_at
ORDER BY 2 ASC