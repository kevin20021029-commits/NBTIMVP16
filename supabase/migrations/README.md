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
