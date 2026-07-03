/*
This query includes the same identity resolution method as the dbt model in this folder,
but is used to combine important client side page views with server side tracks into a 
single table of user actions within the Manager section of the product. 
*/

WITH all_mappings AS ( -- Establish all child-to-parent edges from tables (tracks, pages, aliases)
  SELECT 
    anonymous_id AS alias,
    user_id AS next_alias,
    received_at,
  FROM 
    `manager_events_production`.`tracks`

  UNION ALL
  
  SELECT 
    user_id as alias,
    NULL as next_alias,
    received_at
  FROM 
    `manager_events_production`.`tracks`

  UNION ALL

  SELECT 
    previous_id as alias, 
    user_id as next_alias,
    received_at
  FROM 
    `manager_events_production`.`aliases`

  UNION ALL

  SELECT 
    user_id as alias,
    NULL as next_alias,
    received_at
  FROM 
    `manager_events_production`.`aliases`
  
   UNION ALL
  
  SELECT 
    anonymous_id AS alias,
    user_id AS next_alias,
    received_at,
  FROM 
    `production_gatsby_marketing_website`.`pages`

  UNION ALL
  
  SELECT 
    user_id as alias,
    NULL as next_alias,
    received_at
  FROM 
    `production_gatsby_marketing_website`.`pages`
  
  UNION ALL

  SELECT 
    previous_id as alias, 
    user_id as next_alias,
    received_at
  FROM 
    `production_gatsby_marketing_website`.`aliases`

  UNION ALL

  SELECT 
    user_id as alias,
    NULL as next_alias,
    received_at
  FROM 
    `production_gatsby_marketing_website`.`aliases`
  ),
          
realiases as ( -- Only keep the oldest non-null parent for each child
  SELECT DISTINCT 
    alias,
    FIRST_VALUE(next_alias IGNORE NULLS) OVER (PARTITION BY alias ORDER BY received_at ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as next_alias
  FROM 
    all_mappings
  ),
  
alias_mapping AS (
  -- Traverse the tree upwards and point every node at its root
  SELECT DISTINCT 
    r0.alias,
    COALESCE(r9.next_alias, 
              r9.alias,
              r8.alias,
              r7.alias,
              r6.alias,
              r5.alias,
              r4.alias,
              r3.alias,
              r2.alias,
              r1.alias,
              r0.alias
              ) as mapped_visitor_id
  FROM 
    realiases AS r0
  LEFT JOIN
    realiases AS r1 
  ON r0.next_alias = r1.alias
  LEFT JOIN
    realiases AS r2 
  ON r1.next_alias = r2.alias
  LEFT JOIN
    realiases AS r3 
  ON r2.next_alias = r3.alias
  LEFT JOIN
    realiases AS r4
  ON r3.next_alias = r4.alias
  LEFT JOIN
    realiases AS r5
  ON r4.next_alias = r5.alias
  LEFT JOIN
    realiases AS r6 
  ON r5.next_alias = r6.alias
  LEFT JOIN
    realiases AS r7 
  ON r6.next_alias = r7.alias
  LEFT JOIN
    realiases AS r8 
  ON r7.next_alias = r8.alias
  LEFT JOIN
    realiases AS r9 
  ON r8.next_alias = r9.alias
  ),

mgr_pages as (
  
  SELECT 
    anonymous_id AS anonymous_id,
    context_library_name AS context_library_name,
    context_library_version AS context_library_version,
    event AS event,
    event_text AS event_text,
    first_ab_test AS first_ab_test,
    id AS id,
    loaded_at AS loaded_at,
    original_timestamp AS original_timestamp,
    received_at AS received_at,
    referrer AS referrer,
    sent_at AS sent_at,
    NULL AS team_id,
    timestamp AS timestamp,
    useragent AS user_agent,
    user_id AS user_id,
    uuid_ts AS uuid_ts
  FROM 
    `manager_events_production`.`accept_invitation_page_view`
  
  UNION ALL
  
  SELECT 
    anonymous_id AS anonymous_id,
    context_library_name AS context_library_name,
    context_library_version AS context_library_version,
    event AS event,
    event_text AS event_text,
    first_ab_test AS first_ab_test,
    id AS id,
    loaded_at AS loaded_at,
    original_timestamp AS original_timestamp,
    received_at AS received_at,
    NULL AS referrer,
    sent_at AS sent_at,
    NULL AS `team_id`,
    timestamp AS timestamp,
    NULL AS user_agent,
    NULL AS user_id,
    uuid_ts AS uuid_ts
  FROM 
    `manager_events_production`.`email_password_sign_up_from_invite_accept_page`
    
  UNION ALL
    
  SELECT 
    anonymous_id AS anonymous_id,
    context_library_name AS context_library_name,
    context_library_version AS context_library_version,
    event AS event,
    event_text AS event_text,
    first_ab_test AS first_ab_test,
    id AS id,
    loaded_at AS loaded_at,
    original_timestamp AS original_timestamp,
    received_at AS received_at,
    NULL AS referrer,
    sent_at AS sent_at,
    NULL AS team_id,
    timestamp AS timestamp,
    NULL AS user_agent,
    user_id AS user_id,
    uuid_ts AS uuid_ts
  FROM 
    `manager_events_production`.`free_registration_page_view`
  
  UNION ALL
  
  SELECT 
    NULL AS anonymous_id,
    context_library_name AS context_library_name,
    context_library_version AS context_library_version,
    event AS event,
    event_text AS event_text,
    first_ab_test AS first_ab_test,
    id AS id,
    loaded_at AS loaded_at,
    original_timestamp AS original_timestamp,
    received_at AS received_at,
    referrer AS referrer,
    sent_at AS sent_at,
    team_id AS team_id,
    timestamp AS timestamp,
    useragent AS user_agent,
    user_id AS user_id,
    uuid_ts AS uuid_ts
  FROM 
    `manager_events_production`.`general_settings_view`
  
  UNION ALL
  
  SELECT 
    anonymous_id AS anonymous_id,
    context_library_name AS context_library_name,
    context_library_version AS context_library_version,
    event AS event,
    event_text AS event_text,
    first_ab_test AS first_ab_test,
    id AS id,
    loaded_at AS loaded_at,
    original_timestamp AS original_timestamp,
    received_at AS received_at,
    referrer AS referrer,
    sent_at AS sent_at,
    NULL AS team_id,
    timestamp AS timestamp,
    useragent AS user_agent,
    NULL AS user_id,
    uuid_ts AS uuid_ts
  FROM
    `manager_events_production`.`google_sign_up_from_invite_accept_page`
  
  UNION ALL
  
  SELECT 
    anonymous_id AS anonymous_id,
    context_library_name AS context_library_name,
    context_library_version AS context_library_version,
    event AS event,
    event_text AS event_text,
    first_ab_test AS first_ab_test,
    id AS id,
    loaded_at AS loaded_at,
    original_timestamp AS original_timestamp,
    received_at AS received_at,
    referrer AS referrer,
    sent_at AS sent_at,
    NULL AS team_id,
    timestamp AS timestamp,
    useragent AS user_agent,
    user_id AS user_id,
    uuid_ts AS uuid_ts   
  FROM 
    `manager_events_production`.`log_in_page_view`
  
  UNION ALL
  
  SELECT
    NULL AS anonymous_id,
    context_library_name AS context_library_name,
    context_library_version AS context_library_version,
    event AS event,
    event_text AS event_text,
    first_ab_test AS first_ab_test,
    id AS id,
    loaded_at AS loaded_at,
    original_timestamp AS original_timestamp,
    received_at AS received_at,
    referrer AS referrer,
    sent_at AS sent_at,
    team_id AS team_id,
    timestamp AS timestamp,
    useragent AS user_agent,
    user_id AS user_id,
    uuid_ts AS uuid_ts   
  FROM 
    `manager_events_production`.`manager_home_page_view`
  
  UNION ALL
  
  SELECT 
    NULL AS anonymous_id,
    context_library_name AS context_library_name,
    context_library_version AS context_library_version,
    event AS event,
    event_text AS event_text,
    first_ab_test AS first_ab_test,
    id AS id,
    loaded_at AS loaded_at,
    original_timestamp AS original_timestamp,
    received_at AS received_at,
    referrer AS referrer,
    sent_at AS sent_at,
    team_id AS team_id,
    timestamp AS timestamp,
    useragent AS user_agent,
    user_id AS user_id,
    uuid_ts AS uuid_ts     
  FROM 
    `manager_events_production`.`members_invites_settings_view`
  
  UNION ALL
  
  SELECT 
    NULL AS anonymous_id,
    context_library_name AS context_library_name,
    context_library_version AS context_library_version,
    event AS event,
    event_text AS event_text,
    first_ab_test AS first_ab_test,
    id AS id,
    loaded_at AS loaded_at,
    original_timestamp AS original_timestamp,
    received_at AS received_at,
    NULL AS referrer,
    sent_at AS sent_at,
    team_id AS team_id,
    timestamp AS timestamp,
    NULL AS user_agent,
    user_id AS user_id,
    uuid_ts AS uuid_ts   
  FROM 
    `manager_events_production`.`payment_settings_view`
  
  UNION ALL
  
  SELECT 
    anonymous_id AS anonymous_id,
    context_library_name AS context_library_name,
    context_library_version AS context_library_version,
    event AS event,
    event_text AS event_text,
    first_ab_test AS first_ab_test,
    id AS id,
    loaded_at AS loaded_at,
    original_timestamp AS original_timestamp,
    received_at AS received_at,
    referrer AS referrer,
    sent_at AS sent_at,
    NULL as team_id,
    timestamp AS timestamp,
    useragent AS user_agent,
    user_id AS user_id,
    uuid_ts AS uuid_ts 
  FROM 
    `manager_events_production`.`professional_registration_page_view`
  
  UNION ALL
  
  SELECT 
    anonymous_id AS anonymous_id,
    context_library_name AS context_library_name,
    context_library_version AS context_library_version,
    event AS event,
    event_text AS event_text,
    first_ab_test AS first_ab_test,
    id AS id,
    loaded_at AS loaded_at,
    original_timestamp AS original_timestamp,
    received_at AS received_at,
    referrer AS referrer,
    sent_at AS sent_at,
    NULL AS team_id,
    timestamp AS timestamp,
    useragent AS user_agent,
    user_id AS user_id,
    uuid_ts AS uuid_ts   
  FROM
    `manager_events_production`.`starter_registration_page_view`
  
  UNION ALL
  
  SELECT 
    NULL AS anonymous_id,
    context_library_name AS context_library_name,
    context_library_version AS context_library_version,
    event AS event,
    event_text AS event_text,
    first_ab_test AS first_ab_test,
    id AS id,
    loaded_at AS loaded_at,
    original_timestamp AS original_timestamp,
    received_at AS received_at,
    referrer AS referrer,
    sent_at AS sent_at,
    team_id AS team_id,
    timestamp AS timestamp,
    useragent AS user_agent,
    user_id AS user_id,
    uuid_ts AS uuid_ts     
  FROM 
    `manager_events_production`.`subscription_plan_settings_view`
  
  UNION ALL
  
  SELECT 
    NULL AS anonymous_id,
    context_library_name AS context_library_name,
    context_library_version AS context_library_version,
    event AS event,
    event_text AS event_text,
    first_ab_test AS first_ab_test,
    id AS id,
    loaded_at AS loaded_at,
    original_timestamp AS original_timestamp,
    received_at AS received_at,
    referrer AS referrer,
    sent_at AS sent_at,
    team_id AS team_id,
    timestamp AS timestamp,
    useragent AS user_agent,
    user_id AS user_id,
    uuid_ts AS uuid_ts
  FROM 
    `manager_events_production`.`usage_metrics_settings_view`
  ORDER BY original_timestamp ASC
  ),
  
www_pages AS (
  SELECT
    anonymous_id  AS anonymous_id,
    context_library_name AS context_library_name,
    context_library_version AS context_library_version,
    'website_page' AS event,
    title AS event_text,
    SAFE_CAST(NULL AS STRING) AS first_ab_test,
    id AS id,
    loaded_at AS loaded_at,
    original_timestamp AS original_timestamp,
    received_at AS received_at,
    referrer AS referrer,
    sent_at AS sent_at,
    SAFE_CAST(NULL AS INT64) AS team_id,
    timestamp AS timestamp,
    url AS url,
    context_user_agent AS user_agent,
    SAFE_CAST(NULL AS STRING) AS user_id,
    context_campaign_content AS utm_content,
    context_campaign_medium AS utm_medium,
    context_campaign_name AS utm_campaign,
    context_campaign_source AS utm_source,
    context_campaign_term AS utm_term,
    uuid_ts AS uuid_ts
  FROM
    `production_gatsby_marketing_website`.`pages`
    ),

combi_pages AS (
  SELECT
    anonymous_id,
    context_library_name,
    context_library_version,
    event,
    event_text,
    first_ab_test,
    id,
    loaded_at,
    original_timestamp,
    received_at,
    referrer,
    sent_at,
    team_id,
    timestamp,
    SAFE_CAST(NULL AS STRING) as url,
    user_agent,
    user_id,
    SAFE_CAST(NULL AS STRING) AS utm_content,
    SAFE_CAST(NULL AS STRING) AS utm_medium,
    SAFE_CAST(NULL AS STRING) AS utm_campaign,
    SAFE_CAST(NULL AS STRING) AS utm_source,
    SAFE_CAST(NULL AS STRING) AS utm_term,
    uuid_ts
  FROM
    mgr_pages
  
  UNION ALL
  
  SELECT 
    anonymous_id,
    context_library_name,
    context_library_version,
    event,
    event_text,
    first_ab_test,
    id,
    loaded_at,
    original_timestamp,
    received_at,
    referrer,
    sent_at,
    team_id,
    timestamp,
    url,
    user_agent,
    user_id,
    utm_content,
    utm_medium,
    utm_campaign,
    utm_source,
    utm_term,
    uuid_ts
  FROM
    www_pages
  ORDER BY original_timestamp ASC
  ),
  
mgr_tracks AS (
  SELECT 
    CONCAT(T.received_at, '_', T.id) as event_id,
    T.anonymous_id,
    AM.mapped_visitor_id,
    T.received_at,
    T.event,
    T.event_text,
    T.id as event_uuid,
    T.url,
    T.referrer,
    T.utm_content,
    T.utm_medium,
    T.utm_campaign,
    T.utm_source,
    T.utm_term
  FROM 
    combi_pages AS T
  JOIN
    alias_mapping AS AM
  ON COALESCE(T.user_id, T.anonymous_id) = AM.alias
  )
  
SELECT 
  MT.*,
  SPLIT((SPLIT(MT.referrer, '://')[ORDINAL(2)]), '/')[ORDINAL(1)] as referrer_part,
  DATETIME_DIFF(MT.received_at, LAG(MT.received_at) OVER (PARTITION BY MT.mapped_visitor_id ORDER BY MT.received_at ASC), MINUTE) as idle_time_minutes
FROM
  mgr_tracks as MT
ORDER BY mapped_visitor_id ASC, received_at ASC