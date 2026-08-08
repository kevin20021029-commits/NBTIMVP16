# Supabase RPC Migrations

Dashboard 数据管线依赖以下 Supabase RPC（被 `api/stats.js` 调用）。此前这些 SQL 定义**不在版本控制内**（known-issues #16，与 #14 build-cards.mjs 同类风险），2026-08-08 起纳入本目录。

## 迁移状态

| RPC | 调用点 | 状态 |
| --- | --- | --- |
| `dash_stats` | `api/stats.js` 主查询（funnel/persona/daily/countries/KPI） | **占位** — 待从 Supabase 导出真定义 |
| `dash_times` | `api/stats.js?mode=times`（8 个耗时卡片数据源） | **占位** — 待从 Supabase 导出真定义 |
| `dash_recent` | `api/stats.js?mode=recent`（明细表） | 未入库（同风险，未在本次范围内） |

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
