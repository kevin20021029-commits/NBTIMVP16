-- dash_stats: 主看板聚合（漏斗/人格/日趋势/地区/KPI）
-- 输入（api/stats.js 调用）:
--   t_from      timestamptz   区间起点（+08:00 构造）
--   t_to        timestamptz   区间终点
--   f_country   text          国家过滤，NULL=全部
--   f_event     text          事件过滤，NULL=全部
--   f_version   text          版本过滤，NULL=全部
--   f_excl_speed boolean      排除 speedrun 用户（true 时剔除其全部事件）
-- 返回 JSON（2026-08-08 生产实测示例）:
--   daily        [{ day, users, events }]           按日（Asia/Shanghai 分日）
--   funnel       { event_name: count, ... }          各事件名计数（参与度 tab 用其子集；UI 按「人」语义展示）
--   persona      { persona_code: count, ... }        人格分布（16 型）
--   versions     { test_version: count, ... }        test_version 分布（NULL 标「未知」）
--   all_users    int                                  累计去重用户
--   countries    { country: count, ... }             地区分布
--   active_users int                                 区间去重活跃用户
--   total_events int                                 区间事件总数
-- 示例:
--   {"daily":[{"day":"2026-08-07","users":20,"events":369},{"day":"2026-08-08","users":18,"events":99}],
--    "funnel":{"page_view":35,"test_start":5,"test_completed":5,"share_card_generate_success":5,"deep_dive_expand_click":4,...},
--    "persona":{"FGHC":4,"FGHP":2,...,"RGTC":8,...},
--    "versions":{"16-hk":39,"未知":190,"16题版":182,"48题版":1,"16-question":54,"16���":1,"48���":1},
--    "all_users":37,"countries":{"HK":440,"SG":1,"US":25,"未知":2},"active_users":37,"total_events":468}

-- TODO: 占位——真定义待从 Supabase 导出（见 README「如何补全真定义」）。
-- 已知审计问题（修复前先在此落定真定义，避免改了没保存）:
--   * funnel test_completed=5 与 persona 求和=26 不一致（完成数口径）
--   * f_excl_speed=true 时 total_events 468→80（83% 事件被判 speedrun）
--   * versions 含乱码 16���/48���（入库编码，见 dashboard 审计 I1）
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
BEGIN
  -- TODO: 待补真定义
  RETURN NULL;
END;
$$;
