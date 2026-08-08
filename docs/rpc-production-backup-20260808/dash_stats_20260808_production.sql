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
    -- 人格分布(仅完成测试)
    'persona', (
      select coalesce(jsonb_object_agg(persona_result, cnt), '{}'::jsonb) from (
        select persona_result, count(*) cnt
        from base_ev
        where event_name = 'test_completed' and persona_result is not null
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
end
