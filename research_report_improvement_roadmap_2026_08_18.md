# LLMAOO 阶段性精进方案（2026-08-18）

本文基于 2026-08-18 项目体检报告与 README 阶段状态表，给出按阶段划分的下一步精进路线。核心判断：截至本日，**代码层（阶段〇至五）已全部收口，但实证数据链多处为空，存储/契约治理存在真实缺陷**。精进优先级遵循"先实证后治理、先诚信后装饰"的原则，所有改动坚持零回归（不擅自改 solver 数值、不伪造联网增益）。

## 现状总览（代码 vs 实证）

| 阶段 | 代码层 | 实证数据 | 关键缺口 |
|---|---|---|---|
| 〇/一 契约清理 | 完成 | tevc_submission 为 1.1（与代码 1.2 脱节） | 契约版本未对齐 |
| 二 多目标/energy | 完成 | 门禁全绿（静态） | W_LOAD 敏感性未做 |
| 三.1 基准长跑 | 完成 | `stage7_benchmark.json` 有（7/10 BKS） | MK02/06/09 偏弱待诚实讨论 |
| 三.2 联网增益 | 完成（离线诚实） | `tevc_llm_gain.json` 为离线诚实态 | 联网复跑环境阻塞 |
| 三（补）三目标竞争力 | 完成 | `stageB_sota.json` **缺失** | 五组 HV 对比数据未跑 |
| 一（补）大实例 | 完成 | `stage7_large.json` **缺失** | 结构性 large-config 数据未跑 |
| 五 收敛/回放 | 完成 | `stageC_conv_*.json` **缺失** | mean±std 带数据未跑 |
| 四 pareto 契约 | 完成 | 产物仍为 1.1 | 1.2 重导出未做 |

三个实证文件（`stageB_sota.json`、`stage7_large.json`、`stageC_conv_*.json`）经目录核查均不存在，说明"代码完成"与"数据落地"之间存在明显断档。这是本期精进的第一抓手。

## 阶段 A（立即，P0 — 存储契约对齐，投稿阻塞项）

目标：消除体检报告指出的契约版本脱节，使产物与代码一致。

1. 用当前 1.2 代码重跑 `submit_tevc_offline.m`（或 `_cc_stage0_reexport.bat`），重导出 `results/tevc_submission/tevc_full_result.json` 与 `tevc_multi_result.json`，确认顶层 `contract_version='1.2'` 且 `pareto.energy_n` 字段存在。
2. 在 `exports/export_result_json.m` 顶层补写 `env_state`（`online_real` / `offline_honest`）与 `llm_counts` 字段，使每个 JSON 自带诚实态，第三方无需外部 `env_manifest` 即可反推是否联网产物。
3. 归档 `results/` 根目录 34 个带毫秒时间戳的 `results_*/replay_*.json` 调试遗留（迁移到 `archive/stray_2026_08_18/`，不删除以满足"不擅自删文件"原则），避免 dashboard 递归扫描把调试产物纳入概览表噪音。
4. 重跑后手动核对 dashboard Pareto 页能量色轴：1.2 产物应走 `energy_n` 路径而非回退 `obj3[:,2]`。

## 阶段 B（高优先，P0 — 实证数据链补齐）

目标：把"代码完成但无数据"的三处断档跑出真实产物，闭合证据链。

1. 跑 `tests.stageB_sota`（或 `_cc_*` 对应 bat）：产出 `logs/stageB_sota.json`，含 AOO/Random/GA/PSO/ALNS 五组三目标 HV + Kruskal-Wallis 组间检验；确认门禁 [20] 软失败不阻塞（日志缺失则 SKIP）。
2. 跑 `tests.stage7_large_config`：产出 `logs/stage7_large.json`，验证 MK02/06/09 大实例在自适应预算 large-config 下不劣于默认配置（门禁 [19] 软失败）。
3. 跑 `tests.stageC_conv_batch(N,'MK01',MAXGEN)`（或 `_cc_conv_batch.bat`）：产出 `logs/conv_*.json`，供 `plotly_convergence.py` 聚合 mean±std 收敛带；同步验证 `viz/llm_gain_figures.py` 在离线诚实态输出"full≡modulate≡aoo"标注图。
4. 以上三类数据跑完后，回填 README 状态表对应行的"数据待跑"字样，避免文档与产物长期错位。

## 阶段 C（投稿前，P1 — 方法学诚信强化）

目标：堵住体检指出的建模与叙事隐患。

1. 做 `loadUnb` 归一化敏感性分析：当前 `evaluate.m` 用 `mk_ub` 归一化 loadUnb（物理应为负荷差上界），导致双目标加权和实质偏 makespan。投稿前用不同 `W_LOAD` 取值跑 MK01-10，记录 loadUnb 改善幅度，确认"负荷均衡"目标确有边际贡献；若证明失衡显著，考虑改分母为 `max(loadVec)-min(loadVec)` 理论界（属数值修正，需重跑门禁）。
2. 联网 LLM 增益正文边界：在拿到 `DEEPSEEK_API_KEY`+网络前，论文正文仅声明离线结构化调制贡献（`offline_structured_modulate`），不以"DeepSeek 在线增益"表述；联网复跑步骤已固化于 `env_manifest.json`，待用户注入 Key 后运行 `_cc_llm_gain.bat` 方可写入真实数据。
3. dashboard 概览表语义对齐：修正 `make_overview_table` 中 SOTA 行 `final_best` 取 `max(mk)`（最差）而 benchmark 行取 `aoo_best`（最优）的语义反向问题，统一为"求得值"或显式分列标注，消除误导。

## 阶段 D（投稿图与展示，P2 — 可视化打磨）

目标：提升投稿图与交互展示的严谨度。

1. digital_twin Z 轴间距：`laneDepth*1.6` 与 box 深度 `d=4` 在多作业实例下可能重叠，按作业数自适应间距（或归一化 Z 轴），消除展示瑕疵。
2. 收敛 std 带图：投稿用图须显式标注"来自 N 次独立 run 批量导出"而非单次，避免读者把 mean±std 误解为单次轨迹。
3. 三目标竞争力图：用 `stageB_sota.json` 出 HV/IGD 箱线图 + Kruskal-Wallis p 值标注，强化多目标 rigor 证据。

## 阶段 E（长期，可选 — 算法竞争力）

1. 弱实例 MK02/06/09：当前作 Limitations 诚实讨论。若投稿后需补强，可探索非调参式结构性改进（如动态再调度内循环接入 `dynamic_strategy`/`priority` 契约字段，目前能力位已激活但主链无事件驱动再调度），属新增算法工作，不在本期零回归范围内。
2. AOO novelty：亮点在"LLM 契约引导五策略"，AOO 本身为通用机制；若审稿人质疑对比公平，可在附录补充 GA/PSO 原生多目标改造（而非投影单点）的对照实验。

## 执行顺序建议

A（契约对齐，阻塞）→ B（实证补齐，闭合证据）→ C（诚信强化，堵隐患）→ D（展示打磨）→ E（长期）。A 与 B 可在同一会话内顺序执行（先重导再跑实证）；C3 与 D1 属轻量前端修正可并行。所有步骤遵循"不擅自启动进程、不伪造增益、不删用户文件"的用户安全偏好。

## 参考
- `c:\Users\Joyce_SUN\Desktop\FJSP\research_report_project_review_problem_solution_viz_storage_2026_08_18.md`（体检报告）
- `c:\Users\Joyce_SUN\Desktop\FJSP\README.md`（阶段状态表）
- `c:\Users\Joyce_SUN\Desktop\FJSP\exports\export_result_json.m`（contract_version=1.2）
- `c:\Users\Joyce_SUN\Desktop\FJSP\evaluate.m`（loadUnb 归一化）
- `c:\Users\Joyce_SUN\Desktop\FJSP\viz\dashboard.py`（概览表语义）
