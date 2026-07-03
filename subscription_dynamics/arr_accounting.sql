/*
This query is designed to simplify the visualization of ARR based on another table that 
holds account-level MRR from monthly subscriptions. In additiona to bringing forward
dims relating to each account, it adjusts for monthly vs annual subscription terms and 
buckets each account into a subscription state (new, upgraded, retained, expansion, 
contraction, and churn)

There are some JOIN and WHERE clause filters that were used in validation and research
scenarios that are commented out but preserved for future use
*/

WITH DTSP as (
  SELECT DISTINCT
    DATE_TRUNC(dt, MONTH) as first_of_curr_month,
    DATE((DATE_TRUNC(dt, MONTH) + INTERVAL 1 MONTH) - INTERVAL 1 DAY) as end_of_curr_month,
    DATE(DATE_TRUNC(dt, MONTH) - INTERVAL 1 MONTH) as first_of_prev_month,
    DATE(DATE_TRUNC(dt, MONTH) - INTERVAL 1 DAY) as end_of_prev_month
  FROM
    core.date_spine
  ),
    
ASH AS (
  SELECT
    dt,
    account_id,
    email,
    team_hash,
    COALESCE(mrr, 0) as raw_mrr,
    CASE WHEN DATE(dt) <= DATE(trial_ends_at) THEN 0
       WHEN upgrade_status = 'upgrade' THEN 0
       ELSE COALESCE(mrr, 0)
       END as mrr,
    COALESCE(arr, 0) as raw_arr,
    CASE WHEN DATE(dt) <= DATE(trial_ends_at) THEN 0
       WHEN upgrade_status = 'upgrade' THEN 0
       ELSE COALESCE(arr, 0)
       END as arr,
    is_preset,
    subscription_id,
    CASE WHEN interval_unit = 'months' AND interval_length = 1 THEN 'monthly'
       WHEN interval_unit = 'months' AND interval_length = 12 THEN 'annual'
       ELSE interval_length || ' ' || interval_unit
       END as subscription_cycle,
    subscription_created_at,
    subscription_state,
    canceled_at,
    expires_at,
    is_expired,
    trial_ends_at,
    trial_started_at,
    trial_ended_at,
    trial_status,
    raw_amount,
    account_updated_at,
    account_code,
    company,
    account_created_at,
    account_deleted_at,
    subscription_updated_at,
    activated_at,
    add_ons_total,
    auto_renew,
    collection_method,
    currency,
    current_period_ends_at,
    current_period_started_at,
    current_term_ends_at,
    current_term_started_at,
    expiration_reason,
    paused_at,
    quantity,
    remaining_billing_cycles,
    remaining_pause_cycles,
    renewal_billing_cycles,
    total_billing_cycles,
    unit_amount,
    subsription_uuid,
    plan_id,
    plan_updated_at,
    accounting_code,
    plan_auto_renew,
    plan_code,
    plan_created_at,
    deleted_at,
    plan_description,
    interval_length,
    interval_unit,
    plan_name,
    setup_fee_accounting_code,
    plan_total_billing_cycles,
    plan_trial_length,
    plan_trial_unit,
    hs_contact_id,
    upgrade_status,
    arr_paying,
    arr_trial,
    mrr_paying,
    mrr_trial,
    arr_28d_ago,
    mrr_28d_ago,
    arr_28d_new,
    arr_28d_churn,
    arr_28d_contraction,
    arr_28d_expansion,
    arr_28d_flat,
    nrr_change_28d_for_arr,
    mrr_28d_new,
    mrr_28d_churn,
    mrr_28d_contraction,
    mrr_28d_expansion,
    mrr_28d_flat,
    nrr_change_28d_for_mrr,
    lost_28d_deals,
    won_28d_deals,
    sold_seats,
    lost_deals,
    won_deals
	FROM 
    core_recurly.account_subscription_history
),

L as (
	SELECT DISTINCT
    DTSP.*,
    CURR.dt,
    PREV.dt as prev_dt,
    UNIX_MILLIS(TIMESTAMP(CURR.dt)) as dt_epoch,
    UNIX_MILLIS(TIMESTAMP(PREV.dt)) as prev_dt_epoch,
    CASE WHEN CURR.trial_status = 'paying' AND CURR.upgrade_status = 'upgrade' THEN 'upgraded'
         WHEN CURR.arr > 0 AND (PREV.arr IS NULL OR (PREV.trial_status = 'trial' AND PREV.trial_status IS NULL)) THEN 'new'
         WHEN CURR.arr = PREV.arr AND PREV.arr > 0 THEN 'retained'
         WHEN CURR.arr > PREV.arr AND CURR.subscription_state = 'active' THEN 'expansion'
         WHEN CURR.arr < PREV.arr AND CURR.subscription_state = 'active' THEN 'contraction'
         WHEN CURR.arr = 0 AND PREV.arr > 0 THEN 'churn'
         END as curr_arr_bucket,
    CURR.account_id,
    CURR.email,
    PREV.email as previous_email,
    CURR.team_hash,
    CURR.company,
    CURR.mrr as curr_mrr,
    PREV.mrr as prev_mrr,
    CURR.arr as curr_arr,
    PREV.arr as prev_arr,
    CURR.mrr_paying as curr_mrr_paying,
    PREV.mrr_paying as prev_mrr_paying,
    CURR.arr_paying as curr_arr_paying,
    PREV.arr_paying as prev_arr_paying,
    CURR.is_preset,
    CURR.subscription_id,
    CURR.subscription_created_at,
    PREV.subscription_id as prev_subscription_id,
    PREV.subscription_created_at as prev_subscription_created_at,
    CURR.subscription_state as curr_subscription_state,
    PREV.subscription_state as prev_subscription_state,
    CURR.canceled_at,
    CURR.expires_at,
    CURR.is_expired,
    CURR.subscription_cycle,
    CURR.trial_ends_at,
    CURR.trial_started_at,
    CURR.trial_ended_at,
    CURR.trial_status as curr_trial_status,
    PREV.trial_status as prev_trial_status,
    CURR.raw_amount as curr_raw_amount,
    PREV.raw_amount as prev_raw_amount,
    COALESCE(CURR.arr, 0) - COALESCE(PREV.arr, 0) as arr_change
  FROM
    DTSP
  LEFT JOIN
    ASH as CURR
  ON DTSP.end_of_curr_month = CURR.dt
  LEFT JOIN
    ASH as PREV
  ON DTSP.end_of_prev_month = PREV.dt AND CURR.account_id = PREV.account_id AND PREV.subscription_id = CURR.subscription_id AND (CURR.expires_at >= TIMESTAMP(DTSP.end_of_curr_month) OR CURR.expires_at IS NULL)--AND PREV.subscription_created_at <= CURR.subscription_created_at --AND PREV.subscription_id = CURR.subscription_id
  WHERE
    NOT CURR.is_preset
    AND NOT CURR.is_preset
  )
  
SELECT
  *,
  CASE WHEN curr_trial_status = 'trial' AND DATE_TRUNC(DATE(trial_ends_at), MONTH) >= dt THEN 0
       ELSE arr_change
       END as arr_change_adjusted
FROM
  L
--WHERE
  --end_of_curr_month >= '2022-11-30'
  --AND curr_arr_bucket IS NOT NULL
ORDER BY 1 ASC, account_id ASC