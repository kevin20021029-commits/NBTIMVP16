-- dash_times: 时长与参与度（G5，8 个耗时卡片数据源）
-- 零新埋点：基于 test_progress.params.perQuestionMs[] + 事件时间差计算。
-- 输入（api/stats.js?mode=times 调用）:
--   t_from    timestamptz   区间起点（+08:00 构造）
--   t_to      timestamptz   区间终点
--   f_version text          版本过滤，NULL=全部（按 perQuestionMs 长度推断 16/48 题版）
--   f_lang    text          语言过滤，NULL=全部
--   f_country text          国家过滤，NULL=全部
--   f_ua      text          UA 过滤，NULL=全部
-- 返回 JSON（契约已用 service key 直调 REST 实证，2026-08-08）:
--   total_ms     { '<版本>': {n,p25,p50,p75,p95} }      答题总时长分位数
--   per_question [ { ver, q, n, p50, drop_pct }, ... ]  逐题 P50 与流失率（基数=第1题人数）
--   speedrun     { n, total, pct }                       单题<800ms 占比>70% 的用户占比
--   stages       { landing_to_start: {n,p50,p95}, complete_to_card: {n,p50,p95} }
-- 已知审计问题对照:
--   * C: stages.n 原为【事件对/观测对】数量（landing_to_start = 每个 page_view→test_start 同 user 30 分钟内配对；
--     complete_to_card = 每个 test_completed→(share_card_generate_start/deep_dive_expand_click) 配对），
--     n=181/105 即配对计数，非用户数/完成次数。【用户批准 C 方向一，2026-08-08】已改为按去重用户计
--     （一用户一观测）——需同步更新生产函数（见下方『生产同步』）。
--   * B: speed 判定同 dash_stats（单题<800ms 占比>70%），total 基数=有 test_progress(perQuestionMs) 的用户。
-- 真定义由用户提供（2026-08-08），原样整合。
CREATE OR REPLACE FUNCTION dash_times(
  t_from timestamptz,
  t_to timestamptz,
  f_version text DEFAULT NULL,
  f_lang text DEFAULT NULL,
  f_country text DEFAULT NULL,
  f_ua text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
AS $$
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
  -- 阶段时长:按去重用户计(用户批准 C 方向一,2026-08-08)
  -- landing_to_start:每用户首次 test_start 与其前 30 分钟内最近一次 page_view 的时差(一用户一观测)
  -- complete_to_card:每用户首次 test_completed 与其后 30 分钟内首个卡片/深读的时差(一用户一观测)
  stage as (
    select 'landing_to_start' as stage, (s.ts - p.ts) as dur
    from (
      select user_id, min(ts) as ts
      from public.events
      where event_name = 'test_start' and ts >= t_from and ts < t_to
      group by user_id
    ) s
    cross join lateral (
      select max(e.ts) as ts
      from public.events e
      where e.user_id = s.user_id and e.event_name = 'page_view'
        and e.ts <= s.ts and s.ts - e.ts < interval '30 minutes'
    ) p
    where p.ts is not null
    union all
    select 'complete_to_card' as stage, (c.ts - t.ts) as dur
    from (
      select user_id, min(ts) as ts
      from public.events
      where event_name = 'test_completed' and ts >= t_from and ts < t_to
      group by user_id
    ) t
    cross join lateral (
      select min(e.ts) as ts
      from public.events e
      where e.user_id = t.user_id and e.event_name in ('share_card_generate_start','deep_dive_expand_click')
        and e.ts > t.ts and e.ts - t.ts < interval '30 minutes'
    ) c
    where c.ts is not null
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
end;
$$;
