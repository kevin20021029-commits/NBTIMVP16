# Known Issues — Dashboard 专属（NBTI16 only，非跨仓共享）

> NBTI16 独有（NBTI48 无 dashboard.html），与 `docs/known-issues.md`（跨仓共享）分离。
> 先例：`api/stats.js` 为 16-only dashboard 资产走豁免（同步策略 c）。

## 15. P2(2026-08-08 Dashboard D1): renderEngage 防御 guard 为手动枚举，非结构性防护

dashboard.html renderEngage 的防御 guard 由原 3 元素(kDur16/viewEngage/exclSpeed)补全到 **21 元素**。
核实方式：**手动枚举**——通读 renderEngage 函数体，把每个 `$('id')` 访问点(含传给 getEngageChart 的容器 id perQChart/dropChart/distChart)逐一列出，再加原 guard 的 viewEngage/exclSpeed。非结构性防护（未按「容器→子元素」DOM 树自动推导）。
**风险**：未来参与度视图新增卡片/字段时，若忘记同步更新 engageIds 清单，会再次出现「元素存在但 guard 未覆盖」的同类空指针或静默跳过。后续若做结构性改造，可改为从容器 DOM 查询自动推导必检元素。
注：数量为 21（17 渲染目标 + 2 新增 warn span kDur16Warn/kDur48Warn + viewEngage + exclSpeed），此前汇报中「20」为笔误，以本条为准。


## 16. P2(2026-08-08 Dashboard D2): dash_times RPC 定义不在版本控制内（与 #14 build-cards.mjs 同类）

api/stats.js mode=times 调用 Supabase RPC `dash_times`（dashboard.html 的 8 个耗时卡片数据源）。仓库（含全提交历史）**无任何 SQL 定义/迁移文件**，无 supabase/migrations 目录；唯一相关提交是 a112cc2(dashboard.html G5) 与 fb97351(stats.js mode=times)，均为代码引用，非 RPC 定义。
**定性**：RPC 定义只在 Supabase 数据库内手工创建，存在性/返回 shape 无法从仓库复核——与 #14 build-cards.mjs（工具/定义未入库）同类资产风险。
**影响**：8 卡「dash_times 返回空 vs RPC 缺失返回 500」无法用仓库证据区分；api/stats.js 对 times 的 fetch 用 `.catch(()=>null)` 静默吞错，RPC 缺失时表现为 8 卡全空且无报错。
**已 live 验证（2026-08-08）**：/api/stats?mode=times 返回 200，dash_times RPC 存在于 Supabase DB（complete_to_card n=105、per_question 16 题 p50、speedrun 4）。
**建议**：后续把 Supabase RPC 定义（SQL）纳入版本控制（migrations 目录），避免与 build-cards.mjs 相同的丢失风险。
