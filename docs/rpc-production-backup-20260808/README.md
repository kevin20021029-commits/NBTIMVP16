# RPC 生产定义备份（2026-08-08，A/C/B1 同步前）

**用途**：A/C/B1 修复（迁移文件 `supabase/migrations/20260808000000_dash_stats.sql`、`20260808000001_dash_times.sql`）应用前，当前生产 RPC 定义的快照。**若同步后出现问题，用这两个文件回退生产函数。**

| 文件 | 对应 RPC | 说明 |
| --- | --- | --- |
| `dash_stats_20260808_production.sql` | `dash_stats` | 用户粘贴的当前生产版（含 `speed_ids`/`f_excl_speed`，**不含** A 修复与 B1 排除） |
| `dash_times_20260808_production.sql` | `dash_times` | 用户粘贴的当前生产版（`stage` 为配对计数，**不含** C 修复与 B1 排除） |

**回退方法**：在 Supabase SQL Editor 或 Management API 中，用对应文件里的函数体替换执行（需补 `CREATE OR REPLACE FUNCTION ... AS $$` 包裹，或直接粘贴到原函数编辑框）。

**同步差异对照**：见 `docs/rpc-migration-diff-20260808.md`。
