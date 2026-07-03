/*
This query was designed to be used as a virtual dataset in Superset charts regarding web
traffic conversions that needed a filter for freemail primary account email addresses. 
The primary aggregates are explicitly calculated in this query as opposed to in the 
visualization layer of Superset because we were more interesteed in the trends period over
period than we were of the exact number for a given period (ex: average users / period 
over the last 12 periods in a rolling basis)

A Jinja filter is inscluded in the LCSA CTE that is leveraged by a dashv=board level 
Jinja filter in Superset. This allows for the filter terms to be included in the execution
of the virtual dataset query, as opposed to after the full data set is returned to
in-browser front end. It makes the dashboard perform better when a ciritial mass of charts
are present and refreshing at the same time.
*/

WITH BOTS as (
  SELECT
    anonymous_id
  FROM
    production_gatsby_marketing_website.pages
  WHERE
    context_user_agent LIKE '%PingdomPageSpeed%'
    OR LOWER(context_user_agent) LIKE '%bot%'
  ),

ATT as (
  SELECT
    blended_user_id,
    combined_referrer_source,
    combined_referrer_medium,
    combined_referrer_medium_priority,
    CASE WHEN LOWER(combined_referrer_medium) IN ('cpc', 'ppc', 'paidsearch', 'paid search') THEN 'Paid Search'
         WHEN LOWER(combined_referrer_medium) IN ('display', '+cta+start+free+today', 'sponcon', 'social-paid', 'fbdvby') THEN 'Display'
         WHEN LOWER(combined_referrer_medium) IN ('email', 'nurture') or LOWER(combined_referrer_source) IN ('email') THEN 'Email'
         WHEN LOWER(combined_referrer_medium) IN ('referral') THEN 'Referral'
         WHEN LOWER(combined_referrer_medium) IN ('social', 'rss') THEN 'Social'
         WHEN LOWER(combined_referrer_medium) IN ('organic', 'search') OR (LOWER(combined_referrer_medium) = 'unknown' AND LOWER(combined_referrer_source) IN ('google', 'yahoo!')) THEN 'Organic Search'
         WHEN LOWER(combined_referrer_medium) IN ('direct', '', 'invite') OR combined_referrer_medium IS NULL THEN 'Direct'
         ELSE '(Other)'
         END as channel_grouping
  FROM
    core_wrk.wrk_user_utm_attribution
  ),
  
WV as (
  SELECT DISTINCT
    DATE(DATE_TRUNC(SWS.session_start_tstamp, DAY)) as pageview_date,
    DATE(DATE_TRUNC(SWS.session_start_tstamp, WEEK)) as users_weekly_cohort,
    ATT.channel_grouping,
    SWS.blended_user_id
  FROM
    core_segment_managed_package.segment_web_sessions as SWS
  LEFT JOIN
    ATT
  ON SWS.blended_user_id = ATT.blended_user_id
  WHERE
    SWS.first_event = 'website_page'
    AND SWS.anonymous_id NOT IN (SELECT * FROM BOTS)
  ),

UU as (
  SELECT
    DATE(DATE_TRUNC(WV.pageview_date, WEEK)) as users_weekly_cohort,
    WV.channel_grouping,
    COUNT(DISTINCT WV.blended_user_id) as unique_users
  FROM
    WV
  GROUP BY 1, 2
  ),
 
LCSA AS (
  SELECT 
    HSC.id as hs_contact_id,
    HSC.createdate as hs_contact_created_date,
    HSC.email,
    SUBSTR(HSC.email, INSTR(HSC.email, '@') + 1) as email_domain,
    CASE WHEN SUBSTR(HSC.email, INSTR(HSC.email, '@') + 1) IN ('gmail.com','yahoo.com', 'hotmail.com', 'outlook.com', 'yahoo.ca', 'mail.ru', '163.com', 'yahoo.fr') OR SUBSTR(HSC.email, INSTR(HSC.email, '@') + 1) LIKE 'yahoo%' THEN 'TRUE'
         ELSE 'FALSE'
         END as freemail_creator_email_domain,
    HSC.preset_user_id,
    HSC.associatedcompanyid as hs_company_id,
    EXTRACT(DATETIME FROM TIMESTAMP_MILLIS(CAST(CASE WHEN HSC.became_a_custom_lifecycle_stage_lead_date = '' THEN NULL ELSE HSC.became_a_custom_lifecycle_stage_lead_date END AS INT64))) as became_a_custom_lifecycle_stage_lead_date,
    EXTRACT(DATETIME FROM TIMESTAMP_MILLIS(CAST(CASE WHEN HSC.became_a_custom_lifecycle_stage_marketing_qualified_lead_date = '' THEN NULL ELSE HSC.became_a_custom_lifecycle_stage_marketing_qualified_lead_date END AS INT64))) as became_a_custom_lifecycle_stage_marketing_qualified_lead_date,
    EXTRACT(DATETIME FROM TIMESTAMP_MILLIS(CAST(CASE WHEN HSC.became_a_custom_lifecycle_stage_product_qualified_lead_date = '' THEN NULL ELSE HSC.became_a_custom_lifecycle_stage_product_qualified_lead_date END AS INT64))) as became_a_custom_lifecycle_stage_product_qualified_lead_date,
    EXTRACT(DATETIME FROM TIMESTAMP_MILLIS(CAST(CASE WHEN HSC.became_a_custom_lifecycle_stage_sales_qualified_lead_date = '' THEN NULL ELSE HSC.became_a_custom_lifecycle_stage_sales_qualified_lead_date END AS INT64))) as became_a_custom_lifecycle_stage_sales_qualified_lead_date,
    EXTRACT(DATETIME FROM TIMESTAMP_MILLIS(CAST(CASE WHEN HSC.became_a_custom_lifecycle_stage_opportunity_date = '' THEN NULL ELSE HSC.became_a_custom_lifecycle_stage_opportunity_date END AS INT64))) as became_a_custom_lifecycle_stage_opportunity_date,
    EXTRACT(DATETIME FROM TIMESTAMP_MILLIS(CAST(CASE WHEN HSC.became_a_custom_lifecycle_stage_customer_date = '' THEN NULL ELSE HSC.became_a_custom_lifecycle_stage_customer_date END AS INT64))) as became_a_custom_lifecycle_stage_customer_date,
    EXTRACT(DATETIME FROM TIMESTAMP_MILLIS(CAST(CASE WHEN HSC.became_a_custom_lifecycle_stage_subscriber_date = '' THEN NULL ELSE HSC.became_a_custom_lifecycle_stage_subscriber_date END AS INT64))) as became_a_custom_lifecycle_stage_subscriber_date,
    EXTRACT(DATETIME FROM TIMESTAMP_MILLIS(CAST(CASE WHEN HSC.became_a_custom_lifecycle_stage_evangelist_date = '' THEN NULL ELSE HSC.became_a_custom_lifecycle_stage_evangelist_date END AS INT64))) as became_a_custom_lifecycle_stage_evangelist_date,
    EXTRACT(DATETIME FROM TIMESTAMP_MILLIS(CAST(CASE WHEN HSC.became_a_custom_lifecycle_stage_other_date = '' THEN NULL ELSE HSC.became_a_custom_lifecycle_stage_other_date END AS INT64))) as became_a_custom_lifecycle_stage_other_date
  FROM core_hubspot_fivetran.contact as HSC
  ),

LCS AS (
  SELECT
    *
  FROM
    LCSA
  WHERE
    freemail_creator_email_domain IN ({{ "'" + "', '".join(filter_values('freemail_creator_email_domain')) + "'" }}) --Jinja Filter to be used in a Superset dashboard filter
  ),
  
LEAD as (
  SELECT 
    WV.users_weekly_cohort,
    WV.channel_grouping,
    COUNT(DISTINCT LCS.hs_contact_id) as converted_leads
  FROM
    LCS
  JOIN
    WV
  ON SAFE_CAST(LCS.preset_user_id AS STRING) = WV.blended_user_id AND LCS.became_a_custom_lifecycle_stage_lead_date >= WV.users_weekly_cohort AND DATE(LCS.hs_contact_created_date) >= DATE(WV.users_weekly_cohort)
  GROUP BY 1, 2
  ),

SMQ as (
  SELECT 
    WV.users_weekly_cohort,
    WV.channel_grouping,
    COUNT(DISTINCT LCS.hs_contact_id) as converted_mqls
  FROM
    LCS
  JOIN
    WV
  ON SAFE_CAST(LCS.preset_user_id AS STRING) = WV.blended_user_id AND LCS.became_a_custom_lifecycle_stage_marketing_qualified_lead_date >= WV.users_weekly_cohort AND DATE(LCS.hs_contact_created_date) >= DATE(WV.users_weekly_cohort)
  GROUP BY 1, 2
  ),

SPQ as (
  SELECT 
    WV.users_weekly_cohort,
    WV.channel_grouping,
    COUNT(DISTINCT LCS.hs_contact_id) as converted_pqls
  FROM
    LCS
  JOIN
    WV
  ON SAFE_CAST(LCS.preset_user_id AS STRING) = WV.blended_user_id AND LCS.became_a_custom_lifecycle_stage_product_qualified_lead_date >= WV.users_weekly_cohort AND DATE(LCS.hs_contact_created_date) >= DATE(WV.users_weekly_cohort)
  GROUP BY 1, 2
  ),

SSQ as (
  SELECT 
    WV.users_weekly_cohort,
    WV.channel_grouping,
    COUNT(DISTINCT CASE WHEN LCS.became_a_custom_lifecycle_stage_lead_date IS NOT NULL THEN LCS.hs_contact_id END) as converted_sql_leads,
    COUNT(DISTINCT CASE WHEN LCS.became_a_custom_lifecycle_stage_lead_date IS NULL THEN LCS.hs_contact_id END) as converted_sql_non_leads,
    COUNT(DISTINCT LCS.hs_contact_id) as converted_sql_contacts
  FROM
    LCS
  JOIN
    WV
  ON SAFE_CAST(LCS.preset_user_id AS STRING) = WV.blended_user_id AND LCS.became_a_custom_lifecycle_stage_sales_qualified_lead_date >= WV.users_weekly_cohort AND DATE(LCS.hs_contact_created_date) >= DATE(WV.users_weekly_cohort)
  GROUP BY 1, 2
  ),

SQLD as (
  SELECT
    WV.users_weekly_cohort,
    WV.channel_grouping,
    COUNT(DISTINCT DEAL.deal_id) as converted_SQL_deals
  FROM 
    core_hubspot_managed_package.hubspot__deals as DEAL
  LEFT JOIN
    core_hubspot_managed_package.stg_hubspot__deal_contact as DC
  ON DEAL.deal_id = DC.deal_id
  LEFT JOIN
    LCS
  ON DC.contact_id = LCS.hs_contact_id AND LCS.became_a_custom_lifecycle_stage_sales_qualified_lead_date IS NOT NULL
  JOIN
    WV
  ON SAFE_CAST(LCS.preset_user_id AS STRING) = WV.blended_user_id AND LCS.became_a_custom_lifecycle_stage_sales_qualified_lead_date >= WV.users_weekly_cohort AND DATE(LCS.hs_contact_created_date) >= DATE(WV.users_weekly_cohort)
  WHERE
    DEAL.is_deleted IS FALSE
  GROUP BY 1, 2
  ),

SOPP as (
  SELECT
    WV.users_weekly_cohort,
    WV.channel_grouping,
    COUNT(DISTINCT DEAL.deal_id) as combined_converted_opps,
    COUNT(DISTINCT CASE WHEN LCS.became_a_custom_lifecycle_stage_sales_qualified_lead_date >= WV.users_weekly_cohort THEN DEAL.deal_id END) as converted_opps_from_sqls,
    COUNT(DISTINCT CASE WHEN LCS.became_a_custom_lifecycle_stage_sales_qualified_lead_date < WV.users_weekly_cohort OR LCS.became_a_custom_lifecycle_stage_sales_qualified_lead_date IS NULL THEN DEAL.deal_id END) as converted_opps_from_other_pathways
  FROM 
    core_hubspot_managed_package.hubspot__deals as DEAL
  LEFT JOIN
    core_hubspot_managed_package.stg_hubspot__deal_contact as DC
  ON DEAL.deal_id = DC.deal_id
  LEFT JOIN
    LCS
  ON DC.contact_id = LCS.hs_contact_id AND DATE(LCS.became_a_custom_lifecycle_stage_opportunity_date) >= DATE(DEAL.created_at)
  JOIN
    WV
  ON SAFE_CAST(LCS.preset_user_id AS STRING) = WV.blended_user_id AND LCS.became_a_custom_lifecycle_stage_opportunity_date >= WV.users_weekly_cohort AND DATE(LCS.hs_contact_created_date) >= DATE(WV.users_weekly_cohort)
  WHERE
    DEAL.is_deleted IS FALSE
  GROUP BY 1, 2
  ),

CUST as (
  SELECT
    WV.users_weekly_cohort,
    WV.channel_grouping,
    COUNT(DISTINCT DEAL.deal_id) as combined_converted_customer_deals,
    COUNT(DISTINCT CASE WHEN LCS.became_a_custom_lifecycle_stage_opportunity_date >= WV.users_weekly_cohort THEN DEAL.deal_id END) as converted_customer_deals_from_opp_stage,
    COUNT(DISTINCT CASE WHEN LCS.became_a_custom_lifecycle_stage_opportunity_date < WV.users_weekly_cohort OR LCS.became_a_custom_lifecycle_stage_opportunity_date IS NULL THEN DEAL.deal_id END) as converted_customer_deals_from_other_pathways,
    COUNT(DISTINCT CASE WHEN LCS.became_a_custom_lifecycle_stage_sales_qualified_lead_date >= WV.users_weekly_cohort AND (LCS.became_a_custom_lifecycle_stage_opportunity_date < WV.users_weekly_cohort OR LCS.became_a_custom_lifecycle_stage_opportunity_date IS NULL) THEN DEAL.deal_id END) as converted_customer_deals_direct_from_sql_stage,
    COUNT(DISTINCT CASE WHEN LCS.became_a_custom_lifecycle_stage_product_qualified_lead_date >= WV.users_weekly_cohort AND (LCS.became_a_custom_lifecycle_stage_opportunity_date < WV.users_weekly_cohort OR LCS.became_a_custom_lifecycle_stage_opportunity_date IS NULL) THEN DEAL.deal_id END) as converted_customer_deals_direct_from_pql_stage,
    COUNT(DISTINCT CASE WHEN LCS.became_a_custom_lifecycle_stage_lead_date >= WV.users_weekly_cohort AND (LCS.became_a_custom_lifecycle_stage_opportunity_date < WV.users_weekly_cohort OR LCS.became_a_custom_lifecycle_stage_opportunity_date IS NULL) THEN DEAL.deal_id END) as converted_customer_deals_direct_from_lead_stage
  FROM
    core_hubspot_managed_package.hubspot__deals as DEAL
  LEFT JOIN
    core_hubspot_managed_package.stg_hubspot__deal_contact as DC
  ON DEAL.deal_id = DC.deal_id
  JOIN
    LCS
  ON DC.contact_id = LCS.hs_contact_id AND DATE(LCS.became_a_custom_lifecycle_stage_customer_date) >= DATE(DEAL.created_at)
  JOIN
    WV
  ON SAFE_CAST(LCS.preset_user_id AS STRING) = WV.blended_user_id AND LCS.became_a_custom_lifecycle_stage_customer_date >= WV.users_weekly_cohort AND DATE(LCS.hs_contact_created_date) >= DATE(WV.users_weekly_cohort)
  GROUP BY 1, 2
  )
  
SELECT 
  DATE_TRUNC(DS.dt, WEEK) as period,
  UU.channel_grouping,
  SUM(UU.unique_users) as unique_users,
  SUM(LEAD.converted_leads) as converted_leads,
  SUM(LEAD.converted_leads) / SUM(CASE WHEN UU.unique_users != 0 THEN UU.unique_users END) as lead_conversion_rate,
  SUM(SMQ.converted_mqls) as converted_mqls,
  SUM(SMQ.converted_mqls) / SUM(CASE WHEN LEAD.converted_leads != 0 THEN LEAD.converted_leads END) as mql_conversion_rate,
  SUM(SPQ.converted_pqls) as converted_pqls,
  SUM(SPQ.converted_pqls) / SUM(CASE WHEN LEAD.converted_leads != 0 THEN LEAD.converted_leads END) as pql_conversion_rate,
  SUM(SMQ.converted_mqls) + SUM(CASE WHEN SPQ.converted_pqls != 0 THEN SPQ.converted_pqls END) as converted_mqls_and_pqls,
  SUM(SSQ.converted_sql_leads) as converted_sql_leads,
  SUM(SSQ.converted_sql_non_leads) as converted_sql_non_leads,
  SUM(SSQ.converted_sql_contacts) as converted_sql_contacts,
  SUM(SSQ.converted_sql_leads) / SUM(CASE WHEN LEAD.converted_leads != 0 THEN LEAD.converted_leads END) as sql_lead_conversion_rate,
  SUM(SSQ.converted_sql_non_leads) / SUM(CASE WHEN UU.unique_users != 0 THEN UU.unique_users END) as sql_direct_conversion_rate,
  SUM(SQLD.converted_SQL_deals) as converted_SQL_deals,
  SUM(SOPP.converted_opps_from_sqls) as converted_from_sql_opps,
  SUM(SOPP.converted_opps_from_other_pathways) as converted_opps_from_other_pathways,
  SUM(SOPP.converted_opps_from_sqls) / SUM(CASE WHEN SQLD.converted_SQL_deals != 0 THEN SQLD.converted_SQL_deals END) as opp_conversion_rate,
  SUM(CUST.converted_customer_deals_from_opp_stage) as converted_customer_deals_from_opp_stage,
  SUM(CUST.converted_customer_deals_from_other_pathways) as converted_customer_deals_from_other_pathways,
  SUM(CUST.converted_customer_deals_from_opp_stage) / SUM(CASE WHEN SOPP.converted_opps_from_sqls != 0 THEN SOPP.converted_opps_from_sqls END) as customer_deal_conversion_rate
FROM 
  core.date_spine as DS
LEFT JOIN 
  UU 
ON DS.dt = UU.users_weekly_cohort
LEFT JOIN
  LEAD 
ON DS.dt = LEAD.users_weekly_cohort AND UU.channel_grouping = LEAD.channel_grouping
LEFT JOIN
  SMQ 
ON DS.dt = SMQ.users_weekly_cohort AND UU.channel_grouping = SMQ.channel_grouping
LEFT JOIN
  SPQ 
ON DS.dt = SPQ.users_weekly_cohort AND UU.channel_grouping = SPQ.channel_grouping
LEFT JOIN
  SSQ 
ON DS.dt = SSQ.users_weekly_cohort AND UU.channel_grouping = SSQ.channel_grouping
LEFT JOIN 
  SQLD 
ON DS.dt = SQLD.users_weekly_cohort AND UU.channel_grouping = SQLD.channel_grouping
LEFT JOIN 
  SOPP 
ON DS.dt = SOPP.users_weekly_cohort AND UU.channel_grouping = SOPP.channel_grouping
LEFT JOIN 
  CUST
ON DS.dt = CUST.users_weekly_cohort AND UU.channel_grouping = CUST.channel_grouping
GROUP BY 1, 2

HAVING
  unique_users IS NOT NULL
  
ORDER BY 1 DESC, 2 ASC