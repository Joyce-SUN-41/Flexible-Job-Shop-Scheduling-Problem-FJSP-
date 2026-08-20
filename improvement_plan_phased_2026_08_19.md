# FJSP-LLMAOO 阶段性改进计划（2026-08-19，终版）

> 依据两轮全项目源码评审（问题侧 / 方案侧 / 可视化 / 存储）结论制定。
> 原则：每阶段以回归门禁 `tests.run_all` 或新增长计算日志出，零回归边界清晰；
> solver 数值改动（阶段一）须单独授权后再做，避免破坏既有投稿证据。
> 两轮评审报告：
>   research_report_project_review_problem_solution_viz_storage_2026_final.md
>   research_report_project_review_current_2026.md

---

## 阶段零：清理与收口（低风险，约 30 分钟，立即可做）

**目标**：消除死代码与易误导注释，降低后续改动出错面。

- Z1. 删除 `aoo_engine.m` 第 300 行 `aoo.quality = result.quality;`
  （引用未定义本地变量 `aoo`，MATLAB 动态赋值静默；`result.quality` 已在 293/295 行
  赋值并正常回传，stageB HV 实证已证）。门禁 [10] quality_metrics 不受影响。
- Z2. 在 `results/INDEX.md`（或 README）补「字段量纲表」，显式区分：
  - `loadVec` = 各机负荷和（sum）；`loadUnb` = max−min 不均衡度（unbalance）；
  - `pareto.mk/lb` = 真实值；`pareto.obj3` = 归一化三向量；
  - `trace_makespan` = 真实 makespan 序列；`trace_best` = 归一化加权和（legacy 兼容）。
- Z3. 更正 README/内存中关于「tevc_llm_gain 传 .fjs 崩溃」的旧表述：
  `tevc_llm_gain.m` 实际用 `load_benchmark` 直读 `.fjs`，该路径已可用，旧判断过时。
- Z4. 新增 schema 校验占位：`decode` 输出的 `schedule` 字段名（job/op/machine/start/
  finish/duration）在 `export_result_json` 与 `viz/*` 按列序位置读取，无校验。
  阶段零先加一处注释 + 一个 `schedule_cols` 常量（已存在于导出），后续阶段五统一校验。

**验收**：`tests.run_all` 仍 ALL GREEN；文档量纲表与 schema 注释到位。

---

## 阶段一：修复 loadUnb 归一化分母（最高优先，solver 数值改动，需授权）

**问题**：`evaluate.m` 第 31–32 行用 `mk_ub`（makespan 松弛上界 ~200）同时归一化
makespan 与 loadUnb，而 loadUnb 物理量级仅 ~7 → `ld≈0.035`。即使
`W_MAKESPAN=W_LOAD=1.0` 也实质 makespan 单目标主导，"双目标均衡"名不副实。
C1 实证已量化：`W_LOAD=0` 时 `ld_norm=0.1133`，且 `W_LOAD>0` 或较大 `MAXGEN` 下该路径
偶发 `struct→double` 崩溃（`result.loadUnb`/`result.problem.mk_ub` 偶发 struct 化）。

**方案**：
- A1. 在 `load_data.m` 与 `benchmarks/load_benchmark.m` 的 `assemble_prob` 中新增
  `prob.load_ub` = 负荷差物理上界（保守取法：机器数 × 单工序最大工时，固定、跨代恒定、
  与 loadUnb 同量纲），使 `ld` 落在 [0,1] 且与 `mk` 量级可比。
- A2. `evaluate.m` 改 `ld = loadUnb / max(prob.load_ub, 1e-9);`，并加 struct 防护
  （`result.loadUnb`/`result.problem.mk_ub` 偶发 struct 化一并修复，消除 C1 触发崩溃）。
- A3. 新增单测：构造已知 schedule，断言 `ld` 与 `mk` 数值量级可比（不恒差一个数量级）。

**风险与回滚**：属数值修正，改变默认两目标主链全部相对权衡，必须单独零回归重跑：
门禁 [6] gate_competitiveness + 门禁 [19] large-config。确认 AOO 在两目标口径下不系统性
弱于 Random 后再合并。改动前先用当前代码跑一份保底 `logs/stage7_benchmark.json`（与阶段二并行）。

**验收**：`tests.run_all` 全绿 + `logs/stage7_benchmark.json` 更新；报告 MK01–10 新 gap。

---

## 阶段二：补齐难实例标准长跑与 SOTA 竞争力（高优先，长计算）

**问题**：MK02/03/06/07/10 gap 高达 +57%~+104%（B2 实证 MK09 已 -0.96% 超越 BKS），
SOTA 对比表成立存疑。

**方案**：
- B1. 确认 `data/` 下 10 个 `.fjs` 齐备（`find_fjs` 自动探测）；缺失则从
  `fjsp-instances` 仓库补齐并归档说明。
- B2. 跑 `tests.stage7_run`（N=30，MK01–10）→ `logs/stage7_benchmark.json`（mean/best/std + BKS gap）。
- B3. 跑 `experiment_runs` 五臂（aoo/ga/pso/alns/random，N=30，代表实例 MK01/04/06/09）
  → `logs/stage5_sota_compare.json` + Wilcoxon。
- B4. 若阶段一大改后大实例仍偏弱，针对性增强：试开 `AOO_ACTIVE_DECODE`（默认关），
  或按 `tests/stage7_large_config.m` 思路放大 MK02/06/09 预算。

**验收**：两份 JSON 齐备；论文 SOTA 表有据；仍偏弱实例在 Limitations 诚实讨论。

---

## 阶段三：量化联网 LLM 真实增益（中高优先，依赖环境）

**问题**：离线环境 full ≡ modulate，增益恒 0（环境事实）；难实例/动态/多目标场景
真实增益缺口未补，"双引擎" novelty 证据链关键缺口。

**方案**：
- C1. 在 `DEEPSEEK_API_KEY` + 网络可达机器上跑 `tevc_llm_gain.m`
  （三臂 aoo/modulate/full，场景 MK04/06/09 + dynamic + multi，N=30）
  → `logs/tevc_llm_gain.json`（逐场景 mean/best/std + Wilcoxon）。
- C2. 仅当 full 显著优于 modulate/aoo 时主张"在线 LLM 真实增益"；否则维持诚实离线声明
  （`env_state.mode` 已自带证据）。
- C3. 长期无联网则将"联网增益未量化"列为 Limitations，novelty 聚焦
  "结构化调制代理 + AOO 双引擎架构"而非"在线 LLM 提升"。

**验收**：`logs/tevc_llm_gain.json` 生成；论文增益主张与证据一致。

---

## 阶段四：明确多目标立场（中优先，论文定位 + 可选主线升级）

**问题**：主链默认两目标加权和（`get_best → min(sum(Z,2))`），NSGA-III 仅附加；
论文须避免把附加多目标性归因于默认主链。

**方案（二选一）**：
- D-optA（推荐，低风险）：维持默认两目标加权和主链不动，novelty 诚实定位为
  "LLM 引导的加权和自适应搜索 + 结构化知识调制"；NSGA-III 三目标作「可选扩展/对比」章节
  （门禁 [20] 已校验竞争力）。
- D-optB（高 impact 高工作量）：将 `AOO_THREE_OBJ=true` 的 NSGA-III 主选设为投稿主链路，
  重写默认选择路径，补门禁 [6] 双口径（两目标 vs 三目标）断言；改主链数值语义须全量重跑阶段二。

**验收**：论文 novelty 表述与代码默认路径一致；门禁 [6]/[20] 口径对齐。

---

## 阶段五：契约 / 可视化 / 存储打磨（低优先，收尾）

**新增自本轮评审的问题**（叠加原计划 E1–E3）：

- E1. 收敛图量纲统一：MATLAB `visualize.m` 用归一化 `trace_best`（0.x），
  Python `plotly_convergence`/`dashboard` 用真实 `trace_makespan`。两套并存易让读者混淆。
  **建议收敛只保留真实刻度一套**：MATLAB PNG 也改读真实 `conv_mk`，或文档明确标注双轨差异。
- E2. `digital_twin.py` 从 unpkg CDN 拉 three.js，"自包含可离线"声明与实际冲突。
  离线双击打开 3D 视图空白。改用本地内联 three.js 或 README 明确"需联网首次加载"。
- E3. 结果文件名关联弱：`results_<timestamp>.json` / `conv_<timestamp>.json` 仅靠同目录
  glob 弱关联（dashboard 用 stem 匹配），批量多场景（已现 `results/tevc_submission/`
  子目录）易混。**建议文件名嵌入 `scenario+seed+cfg_hash`**，并用 ISO8601 UTC 时间戳。
- E4. schema 隐形耦合：导出/viz 按列序位置读 `schedule`，无校验。阶段零已加常量占位，
  此处统一加一个 `validate_schedule(rows)` 校验层（列数=6、非负 finish≥start）。
- E5. dashboard 多文件风险：`discover_results` 递归 glob 多 pattern 仅去重无强制版本校验，
  历史 `results_*.json` 并存易选错。建议在 selectbox 显示 `generated`/`contract_version`/
  `scenario`，并对 <1.2 旧契约仍告警（已有）。
- E6. `pareto.OS/MS` 完整染色体随非支配解重复序列化，对可视化无必要，可瘦身
  （仅存 mk/lb/obj3/energy_n；染色体按需另存）。
- E7. README 标注 `conv` std 带已用真实 `trace_makespan`（conv_mk 已为真），避免误读。
- E8. 补「五策略 × 三增益映射表」+ 单测断言每个增益至少影响一个算子参数，显式化隐式耦合。

**验收**：收敛图仅真实刻度；digital twin 离线可用或文档声明；文件名带 hash；
schema 校验入 `tests.run_all`（建议新增门禁 [21]）。

---

## 执行顺序与依赖

1. 阶段零（清理）→ 立即可做，无风险。
2. 阶段一（loadUnb 分母）需用户授权数值改动 → 授权后做，重跑门禁 [6][19]。
3. 阶段二（长跑）可与阶段一并行（改动前先跑保底基线，改动后再跑对比）。
4. 阶段三（联网增益）依赖外部环境与 Key，独立轨道。
5. 阶段四（多目标立场）为论文层决策，不阻塞代码。
6. 阶段五（契约/可视化/存储打磨）随时可做，收尾。

**优先级总排序**：阶段一（数值真实性）＞ 阶段二（SOTA 证据）＞ 阶段三（增益证据）
＞ 阶段四（论文定位）＞ 阶段五（健壮性）＞ 阶段零（清理，先行）。

**总体验收门槛**：`tests.run_all` ALL GREEN；`logs/` 下 `stage7_benchmark.json` /
`stage5_sota_compare.json` / （可选）`tevc_llm_gain.json` / `stageB_sota.json` 齐备；
论文 novelty 表述与代码默认路径、诚实声明一致；收敛图量纲统一、digital twin 离线可用。

---

## 关联产物
- 评审报告：`research_report_project_review_problem_solution_viz_storage_2026_final.md`
- 回归入口：`tests.run_all`（门禁 [1]–[20]；建议新增 [21] schema/映射表单测）
- 长计算：`tests.stage7_run` / `experiment_runs` / `tevc_llm_gain` / `tests.stageB_sota`
