{{
  config(
    alias='wrk_initial_serial_alias_mapping',
    materialized='table'
  )
}}

/*
This series of transformations generates a map of anonymous_ids to a defined internal user_id,
in our case the manager user_id. We take all of the Segment tables where both an anonymous_id
and a user_id could be present across Segment sources and try to combine them into one final
table.

For every row where both anonymous_id and user_id are present in each table, a relation
is generated in the first SELECT of each pair. In the second SELECT we use the user_id
as the final step by relating it to NULL, which will terminate the chain of relations
when combined later.

The method for this was adapted from a series of blog posts from Looker on identity
resolution using Segment circa 2016/2017
*/

WITH all_mappings AS ( -- Establish all child-to-parent edges from tables (tracks, pages, aliases)

    {% set mapping_sources = [['manager_events_production', 'tracks'],['manager_events_production', 'aliases'],['manager_events_production', 'pages'],['manager_events_production', 'identifies'],['production_gatsby_marketing_website', 'aliases']] %}

    {% for mapping_source in mapping_sources %}
    SELECT
        {% if mapping_source[1] == "aliases" %}previous_id{% else %}anonymous_id{% endif %} AS alias,
        user_id AS next_alias,
        received_at,
    FROM
        {{ source(mapping_source[0], mapping_source[1]) }}

    UNION ALL

    SELECT
        user_id AS alias,
        NULL AS next_alias,
        received_at,
    FROM
        {{ source(mapping_source[0], mapping_source[1]) }}

    {%- if not loop.last %}
    UNION ALL
    {% endif -%}

  {% endfor %}
),

realiases AS ( -- Only keep the oldest non-null parent for each child
    SELECT DISTINCT
        alias,
        FIRST_VALUE(
            next_alias IGNORE NULLS
        ) OVER (
            PARTITION BY alias ORDER BY received_at ASC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS next_alias,
        received_at AS first_seen_at,
    FROM
        all_mappings
),

init_mapping AS (
    -- Traverse the tree upwards and point every node at its root
    SELECT DISTINCT
        r0.alias,

        {# the following self joins the `realiases` cte and constructs the relationship tree #}
        {% set num_loops = 10 %}
        COALESCE(r9.next_alias,
                 {% for n in range(num_loops) %}
                 r{{num_loops - 1 - n}}.alias
              {%- if not loop.last %},{% endif -%}
             {% endfor %}
        ) AS mapped_visitor_id,
        r0.first_seen_at,
        {% for n in range(num_loops) %}
        {% if loop.first %}FROM{% else %}LEFT JOIN {% endif %}
            realiases AS r{{ n }}
        {% if not loop.first %}ON r{{ n - 1 }}.next_alias = r{{ n }}.alias{% endif %}
    {% endfor %}
),

MFSA AS (
    -- determine minimum first seen at date for give alias, mapped_visitor_id pair
    SELECT DISTINCT
        alias,
        mapped_visitor_id,
        first_seen_at,
        MIN(first_seen_at) OVER (PARTITION BY alias, mapped_visitor_id) AS min_first_seen_at,
    FROM
        init_mapping
)

SELECT DISTINCT
    IM1.alias,
    IM1.mapped_visitor_id,
    IM1.first_seen_at,
FROM
    init_mapping AS IM1
INNER JOIN
    MFSA AS IM2
    ON IM1.alias = IM2.alias
        AND IM1.mapped_visitor_id = IM2.mapped_visitor_id
        AND IM1.first_seen_at = IM2.min_first_seen_at