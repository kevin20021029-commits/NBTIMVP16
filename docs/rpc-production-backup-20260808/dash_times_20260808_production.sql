declare
  r jsonb;
begin
  with tp as (
    select e.id, e.user_id, e.ts, e.params, e.country, e.lang,
           case when jsonb_array_length(e.params->'perQuestionMs') >= 40 then '48题版' else '16题版' end as ver,
           coalesce(e.params->>'uaBucket', 'unknown') as ua_bucket,
           coalesce((e.params->>'isDiag')::boolean, false) as is_diag
    from public.events e
    where e.event_name = 'test_progress'
      and e.ts >= t_from and e.ts < t_to
      and (f_version is null or
           case when jsonb_array_length(e.params->'perQuestionMs') >= 40 then '48题版' else '16题版' end = f_version)
      and (f_lang is null or e.lang = f_lang)
      and (f_country is null or e.country = f_country)
      and (f_ua is null or coalesce(e.params->>'uaBucket','unknown') = f_ua)
  ),
  perq as (
    select tp.ver, tp.user_id, x.ordinality as q, (x.value)::numeric as ms
    from tp, jsonb_array_elements_text(tp.params->'perQuestionMs') with ordinality x
  ),
  -- 总时长(每题耗时之和)
  totals as (
    select ver, user_id, sum(ms) as total_ms from perq group by ver, user_id
  ),
  -- speedrun:单题 <800ms 占比 >70%
  speed as (
    select user_id from perq
    group by ver, user_id
    having (count(*) filter (where ms < 800))::float / count(*) > 0.7
  ),
  -- 每版第 1 题人数(逐题流失率的基数)
  first_q as (
    select ver, count(distinct user_id) as n1 from perq where q = 1 group by ver
  ),
  -- 阶段时长:事件时间差(同 user_id 相邻事件,±30 分钟内)
  stage as (
    select 'landing_to_start' as stage, (e2.ts - e1.ts) as dur
    from public.events e1
    join public.events e2 on e2.user_id = e1.user_id
      and e2.event_name = 'test_start' and e2.ts > e1.ts
      and e2.ts - e1.ts < interval '30 minutes'
    where e1.event_name = 'page_view'
      and e1.ts >= t_from and e1.ts < t_to
    union all
    select 'complete_to_card' as stage, (e2.ts - e1.ts) as dur
    from public.events e1
    join public.events e2 on e2.user_id = e1.user_id
      and e2.event_name in ('share_card_generate_start','deep_dive_expand_click')
      and e2.ts > e1.ts and e2.ts - e1.ts < interval '30 minutes'
    where e1.event_name = 'test_completed'
      and e1.ts >= t_from and e1.ts < t_to
  )
  select jsonb_build_object(
    -- 答题总时长分位数(ms),16/48 分开
    'total_ms', (
      select coalesce(jsonb_object_agg(ver, j), '{}'::jsonb) from (
        select ver, jsonb_build_object(
          'n', count(*),
          'p25', percentile_cont(0.25) within group (order by total_ms),
          'p50', percentile_cont(0.50) within group (order by total_ms),
          'p75', percentile_cont(0.75) within group (order by total_ms),
          'p95', percentile_cont(0.95) within group (order by total_ms)
        ) as j
        from totals group by ver
      ) t
    ),
    -- 单题耗时(每题 P50)+ 逐题流失率(答到该题的人数 / 答到第1题的人数)
    'per_question', (
      select coalesce(jsonb_agg(j order by ver, q_num), '[]'::jsonb) from (
        select p.ver, p.q as q_num,
          jsonb_build_object(
            'ver', p.ver,
            'q', p.q,
            'n', count(distinct p.user_id),
            'p50', percentile_cont(0.5) within group (order by p.ms),
            'drop_pct', round(100 * (1 - count(distinct p.user_id)::numeric / nullif(f.n1, 0)), 1)
          ) as j
        from perq p left join first_q f on f.ver = p.ver
        group by p.ver, p.q, f.n1
      ) t
    ),
    -- speedrun 占比
    'speedrun', (
      select jsonb_build_object(
        'n', count(distinct user_id),
        'total', (select count(distinct user_id) from tp),
        'pct', round(100 * count(distinct user_id)::numeric /
          nullif((select count(distinct user_id) from tp), 0), 1)
      ) from speed
    ),
    -- 阶段时长分布(毫秒)
    'stages', (
      select coalesce(jsonb_object_agg(stage, j), '{}'::jsonb) from (
        select stage, jsonb_build_object(
          'n', count(*),
          'p50', round(percentile_cont(0.5) within group (order by extract(epoch from dur)) * 1000),
          'p95', round(percentile_cont(0.95) within group (order by extract(epoch from dur)) * 1000)
        ) as j
        from stage group by stage
      ) t
    )
  ) into r;
  return r;
end
