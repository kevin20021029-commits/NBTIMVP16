-- dash_times: 时长与参与度（G5，8 个耗时卡片数据源）
-- 零新埋点：基于 test_progress.params.perQuestionMs[] + 事件时间差计算。
-- 输入（api/stats.js?mode=times 调用）:
--   t_from    timestamptz   区间起点（+08:00 构造）
--   t_to      timestamptz   区间终点
--   f_version text          版本过滤，NULL=全部
--   f_lang    text          语言过滤，NULL=全部
--   f_country text          国家过滤，NULL=全部
--   f_ua      text          UA 过滤，NULL=全部
-- 返回 JSON（2026-08-08 生产实测示例）:
--   stages          { landing_to_start: {n,p50,p95}, complete_to_card: {n,p50,p95} }
--   speedrun        { n, pct, total }
--   total_ms        { '<版本>': {n,p25,p50,p75,p95} }      版本键如 16题版/48题版
--   per_question    [ { ver, q, p50, n, drop_pct }, ... ]   逐题 P50 与流失率
-- 示例:
--   {"stages":{"complete_to_card":{"n":105,"p50":160475,"p95":1268728},
--              "landing_to_start":{"n":181,"p50":558896,"p95":1447832}},
--    "speedrun":{"n":4,"pct":100,"total":4},
--    "total_ms":{"16题版":{"n":4,"p25":9153.5,"p50":10067.5,"p75":24996.75,"p95":60067.35}},
--    "per_question":[{"n":4,"q":1,"p50":575,"ver":"16题版","drop_pct":0},...]}

-- TODO: 占位——真定义待从 Supabase 导出（见 README「如何补全真定义」）。
-- 已知审计问题（修复前先在此落定真定义，避免改了没保存）:
--   * stages.n=181/105 与任何计数口径对不上（疑似按会话/观测对计数，UI 当样本数展示）
--   * speedrun.total=4 但 dash_stats f_excl_speed 移除 83% 事件（判定口径不一致）
--   * total_ms 缺 48题版 条目（48 题 test_progress 无数据，kDur48 合法显示 —）
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
BEGIN
  -- TODO: 待补真定义
  RETURN NULL;
END;
$$;
