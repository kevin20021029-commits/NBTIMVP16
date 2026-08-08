# Supabase RPC Migrations

Dashboard 数据管线依赖以下 Supabase RPC（被 `api/stats.js` 调用）。此前这些 SQL 定义**不在版本控制内**（known-issues #16，与 #14 build-cards.mjs 同类风险），2026-08-08 起纳入本目录。

## 迁移状态

| RPC | 调用点 | 状态 |
| --- | --- | --- |
| `dash_stats` | `api/stats.js` 主查询（funnel/persona/daily/countries/KPI） | **真定义已入库**（用户提供，含 speed_ids/excl_speed） |
| `dash_times` | `api/stats.js?mode=times`（8 个耗时卡片数据源） | **真定义已入库**（用户提供） |
| `dash_recent` | `api/stats.js?mode=recent`（明细表） | 存在已确认（OpenAPI spec）；未入库，同风险 |

**获取 SQL 体受阻说明**：service key 走 PostgREST 只能验证签名与调用（pg_get_functiondef 不可执行）；Management API 需独立 `sbp_` 令牌；pg-meta 内部端点未对公网暴露（404）。dash_stats/dash_times 真定义均已由用户控制台复制提供并整合。

**用户提供文件存档**：`incoming/dash_stats_block1.sql`（当前 dash_stats，含 speed 过滤，已整合）；`incoming/dash_stats_block2.sql`（无 speed 过滤的旧版 dash_stats，历史参考，未建为函数）；`incoming/dash_times_real.sql`（dash_times，已整合）。

## B1：统计层排除 4 个 bot 用户（2026-08-08，用户批准）

两个迁移文件头部加入 `bot_ids` CTE，排除以下 4 个已识别 bot 用户（判定：test_progress 单题耗时 <800ms 占比 >70%，与 speed_ids 同口径）：
- `64972fec-8c96-43b0-80a1-8572fb169167`（08-07 45 事件）
- `3c3557ac-ade2-4189-9edf-e8cd0359c3d6`（08-07 300 事件）
- `e2f509c5-47e9-426f-bf7e-eb07b2878267`（08-08 35 事件）
- `d304cf41-7e5b-4780-a9d9-90793221f9e6`（08-08 20 事件，仍在持续）

**机制理由**：统计层（RPC 聚合）排除，与 B2 入口层拦截相互独立。选 SQL 层而非 dashboard 侧过滤：①搭 A/C 生产同步一次到位；②聚合层统一排除（漏斗/人格/日趋势/时长全口径一致）；③dashboard 侧无法过滤已聚合的 API 响应。
**可回退性**：纯附加 WHERE 过滤，不删不改任何数据；删除 `bot_ids` CTE 即恢复。与 B2（入口层拦截）相互独立、可单独回退。
**影响**：4 个 bot 贡献了约 400 条事件（总 500 中的 80%），且是全部 test_progress 发送者 → 排除后 16题版 答题时长/单题耗时/speedrun 卡将显示空/—（真实用户尚无 test_duration 数据），待真实用户完成后填充。

## 生产同步（重要）

迁移文件是**版本控制的预期定义**，但 Supabase 里运行的是独立函数，**改迁移文件不会自动改生产 RPC**。以下改动需同步应用到生产函数（否则生产行为不变）：
- 2026-08-08 A 修复：dash_stats 的 persona 改为每用户取首次结果 + count(distinct user_id)。
- 2026-08-08 C 修复：dash_times 的 stage 改为按去重用户计（一用户一观测）。

应用方式（任选其一，需 Supabase 权限）：
1. **Supabase 控制台** → SQL Editor → 粘贴迁移文件里的完整 `CREATE OR REPLACE FUNCTION` → Run。
2. **Management API**（`sbp_` 令牌）：`POST /v1/projects/{ref}/database/query`，body `{"query": "<完整 CREATE OR REPLACE FUNCTION SQL>"}`。
3. **psql/DB 连接串**：执行迁移文件 SQL。

`ref=jxgcnicskcqwzotbeckb`。

## 如何补全真定义

有 Supabase 访问权限时（Management API 或 psql/service key），用以下方式导出并**替换**对应迁移文件里的占位体：

- `select pg_get_functiondef('dash_stats'::regproc);`（或 `dash_times`）
- 或 Supabase Dashboard → Database → Functions → 复制定义。

替换后：
1. 保持文件名（时间戳前缀 `20260808...`）。
2. 在占位体上方保留「输入/输出契约」注释（是真实调用/返回的存档，勿删）。
3. 若定义有变更，新建时间戳更大的迁移文件，勿改旧文件（可回放/审计）。

## 输入/输出契约（真实存档，2026-08-08 生产实测）

见各文件头注释。返回 JSON 结构来自生产 `api/stats` 真实响应，可作为 SQL 重写后的回归对照。
