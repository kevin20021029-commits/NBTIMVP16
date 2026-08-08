-- dash_stats: 主看板聚合（漏斗/人格/日趋势/地区/KPI）
-- 输入（api/stats.js 调用）:
--   t_from      timestamptz   区间起点（+08:00 构造）
--   t_to        timestamptz   区间终点
--   f_country   text          国家过滤，NULL=全部
--   f_event     text          事件过滤，NULL=全部
--   f_version   text          版本过滤，NULL=全部
--   f_excl_speed boolean      排除 speedrun 用户（true 时剔除其全部事件）
-- 返回 JSON（契约已用 service key 直调 REST 实证，2026-08-08）:
--   total_events / active_users / all_users
--   funnel       { event_name: 去重 user_id 数 }   （按去重用户计数）
--   persona      { persona_code: count(*) }         （test_completed 事件数，重测会累加）
--   countries / daily / versions
-- 已知审计问题对照:
--   * A: persona 原按 count(*)（完成事件数，重测累加）而 funnel 按 count(distinct user_id）
--     → 26 次完成事件 vs 5 个去重完成用户。【用户批准 A 修复，2026-08-08】已改为每用户取首次结果、
--     count(distinct user_id)——需同步更新生产函数（见下方『生产同步』）。
--   * B: speed_ids 用 params.perQuestionMs 单题耗时 <800ms 占比 >70% 判 speedrun；
--     f_excl_speed=true 时剔除其全部事件 → 生产 468→80（4 个 bot 用户占 83% 事件，数据质量而非阈值）
-- 注意：用户曾另贴一份无 f_excl_speed 的旧版 dash_stats（dash_stats_block2.sql），仅作历史参考，非当前定义。
CREATE OR REPLACE FUNCTION dash_stats(
  t_from timestamptz,
  t_to timestamptz,
  f_country text DEFAULT NULL,
  f_event text DEFAULT NULL,
  f_version text DEFAULT NULL,
  f_excl_speed boolean DEFAULT false
)
RETURNS json
LANGUAGE plpgsql
AS $$
declare
  r jsonb;
begin
  with speed_ids as (
    -- speedrun 定义:test_progress 中单题耗时 <800ms 占比 >70% 的用户
    select user_id from (
      select user_id,
        (count(*) filter (where (x.value)::numeric < 800))::float / count(*) as fast_ratio
      from public.events e
        cross join lateral jsonb_array_elements_text(e.params->'perQuestionMs') x
      where e.event_name = 'test_progress'
        and e.ts >= t_from and e.ts < t_to
        and coalesce((e.params->>'isDiag')::boolean, false) = false
      group by user_id
    ) s
    where fast_ratio > 0.7
  ),
  base as (
    select * from public.events
    where ts >= t_from and ts < t_to
      and (f_country is null or country = f_country)
      and (f_version is null or test_version = f_version)
      and (not f_excl_speed or user_id not in (select user_id from speed_ids))
  ),
  base_ev as (
    select * from base
    where (f_event is null or event_name = f_event)
  )
  select jsonb_build_object(
    -- KPI:范围内行为数 / 范围内活跃用户 / 全时总用户
    'total_events', (select count(*) from base_ev),
    'active_users', (select count(distinct user_id) from base_ev),
    'all_users',    (select count(distinct user_id) from public.events),
    -- 漏斗:始终按全事件统计(不受行为过滤影响);按去重用户计数,
    -- 避免一人多次生成分享卡导致漏斗级数不递减(如 >100% 转化)
    'funnel', (
      select coalesce(jsonb_object_agg(event_name, cnt), '{}'::jsonb) from (
        select event_name, count(distinct user_id) cnt from base group by event_name
      ) s
    ),
    -- 人格分布(仅完成测试;每用户取首次结果,按去重用户计数——用户批准 A 方案,2026-08-08)
    'persona', (
      select coalesce(jsonb_object_agg(persona_result, cnt), '{}'::jsonb) from (
        select persona_result, count(*) cnt
        from (
          select user_id, persona_result,
                 row_number() over (partition by user_id order by ts) rn
          from base_ev
          where event_name = 'test_completed' and persona_result is not null
        ) first
        where rn = 1
        group by persona_result
      ) s
    ),
    -- 地区分布
    'countries', (
      select coalesce(jsonb_object_agg(c, cnt), '{}'::jsonb) from (
        select coalesce(nullif(country, ''), '未知') c, count(*) cnt
        from base_ev group by 1
      ) s
    ),
    -- 日趋势(Asia/Shanghai 时区)
    'daily', (
      select coalesce(jsonb_agg(d order by d.day), '[]'::jsonb) from (
        select to_char(date_trunc('day', ts at time zone 'Asia/Shanghai'), 'YYYY-MM-DD') as "day",
               count(*) events,
               count(distinct user_id) users
        from base_ev group by 1
      ) d
    ),
    -- 版本分布(16/48)
    'versions', (
      select coalesce(jsonb_object_agg(v, cnt), '{}'::jsonb) from (
        select coalesce(nullif(test_version, ''), '未知') v, count(*) cnt
        from base_ev group by 1
      ) s
    )
  ) into r;
  return r;
end;
$$;
