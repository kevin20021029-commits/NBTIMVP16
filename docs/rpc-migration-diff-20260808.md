# RPC 迁移差异对照：当前生产版 vs 迁移版（ee7c424）

对比对象：
- 当前生产版：`docs/rpc-production-backup-20260808/`（用户粘贴的现有定义）
- 迁移版：`supabase/migrations/20260808000000_dash_stats.sql`、`20260808000001_dash_times.sql`（含 A/C/B1 修复）

共 3 处差异：**A**（persona 口径）、**C**（stage 口径）、**B1**（bot 排除）。

---

## 差异 1 · A：dash_stats persona 改为去重用户、每用户取首次结果

**生产版（before）** — 按完成事件数 count(*)，重测累加：
```sql
'persona', (
  select coalesce(jsonb_object_agg(persona_result, cnt), '{}'::jsonb) from (
    select persona_result, count(*) cnt
    from base_ev
    where event_name = 'test_completed' and persona_result is not null
    group by persona_result
  ) s
),
```

**迁移版（after）** — 每用户按 ts 取首次 test_completed 结果，再按人格 count（=去重用户）：
```sql
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
```
效果：persona sum 从 27（重测累加）→ 去重用户数（funnel test_completed≈5）。

---

## 差异 2 · B1：统计层排除 4 个 bot 用户（dash_stats + dash_times）

**生产版（before）** — 无 bot 排除（仅 f_excl_speed 可选排除 speedrun）：
```sql
base as (
  select * from public.events
  where ts >= t_from and ts < t_to
    and (f_country is null or country = f_country)
    and (f_version is null or test_version = f_version)
    and (not f_excl_speed or user_id not in (select user_id from speed_ids))
),
```

**迁移版（after）** — 新增 `bot_ids` CTE + 各查询排除：
```sql
with bot_ids as (
  select unnest(array[
    '64972fec-8c96-43b0-80a1-8572fb169167',
    '3c3557ac-ade2-4189-9edf-e8cd0359c3d6',
    'e2f509c5-47e9-426f-bf7e-eb07b2878267',
    'd304cf41-7e5b-4780-a9d9-90793221f9e6'
  ]::text[]) as uid
),
...
base as (
  ...
  and (not f_excl_speed or user_id not in (select user_id from speed_ids))
  and user_id not in (select uid from bot_ids)   -- B1
),
```
- dash_stats：`base`（total_events/funnel/persona/countries/daily/versions 全部基于 base）+ `all_users`（`where user_id not in (select uid from bot_ids)`）。
- dash_times：`tp`（total_ms/per_question/speedrun 全部基于 tp）+ `stage`（landing_to_start 的 test_start 子查询、complete_to_card 的 test_completed 子查询）排除。
效果：排除 4 bot 的 408 事件（516→108）。

---

## 差异 3 · C：dash_times stage 改为按去重用户计（一用户一观测）

**生产版（before）** — 事件对计数（每个 page_view→test_start / test_completed→card/deep_dive 配对一行，n=配对数）：
```sql
stage as (
  select 'landing_to_start' as stage, (e2.ts - e1.ts) as dur
  from public.events e1
  join public.events e2 on e2.user_id = e1.user_id
    and e2.event_name = 'test_start' and e2.ts > e1.ts
    and e2.ts - e1.ts < interval '30 minutes'
  where e1.event_name = 'page_view' and e1.ts >= t_from and e1.ts < t_to
  union all
  select 'complete_to_card' as stage, (e2.ts - e1.ts) as dur
  from public.events e1
  join public.events e2 on e2.user_id = e1.user_id
    and e2.event_name in ('share_card_generate_start','deep_dive_expand_click')
    and e2.ts > e1.ts and e2.ts - e1.ts < interval '30 minutes'
  where e1.event_name = 'test_completed' and e1.ts >= t_from and e1.ts < t_to
),
```

**迁移版（after）** — 每用户一观测（首次 test_start→前 30 分钟内最近 page_view；首次 test_completed→后 30 分钟内首个 card/deep_dive），n=去重用户数：
```sql
stage as (
  select 'landing_to_start' as stage, (s.ts - p.ts) as dur
  from (
    select user_id, min(ts) as ts
    from public.events
    where event_name = 'test_start' and ts >= t_from and ts < t_to
      and user_id not in (select uid from bot_ids)
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
      and user_id not in (select uid from bot_ids)
    group by user_id
  ) t
  cross join lateral (
    select min(e.ts) as ts
    from public.events e
    where e.user_id = t.user_id and e.event_name in ('share_card_generate_start','deep_dive_expand_click')
      and e.ts > t.ts and e.ts - t.ts < interval '30 minutes'
  ) c
  where c.ts is not null
),
```
效果：stages.n 从配对计数（181/105）→ 去重用户数（≈5）。

---

## 备注
- `dash_stats` 无 C 差异；`dash_times` 无 A 差异。
- 两处迁移文件均已包含上述差异；用户按 `supabase/migrations/README.md`「生产同步」执行完整 `CREATE OR REPLACE FUNCTION` 即可。
- 回退依据：`docs/rpc-production-backup-20260808/`。
