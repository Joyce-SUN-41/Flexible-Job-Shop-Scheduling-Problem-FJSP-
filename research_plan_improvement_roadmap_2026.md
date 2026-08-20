# FJSP-LLMAOO 阶段性改进方案（投稿 IEEE TEVC）

> 依据：2026-08-16 现状评审（`research_report_project_review_current_2026.md`）。
> 设计原则：① 不破坏现有 ADDITIVE / 零回归纪律；② 低风险高收益优先；③ 复用既有
> Stage A–H、`tests/run_all.m` 门禁、`_cc_*.bat` 长跑脚本、实验脚手架（已具备），不重复造轮子。
> 总目标：把"LLM 引导的加权和自适应搜索"升级为可被 TEVC 审稿接受的多目标 + 真实 LLM 增益证据链。

---

## 阶段一：结果存储与可视化契约清理（低风险，1–2 天）

目标：消除评审指出的契约语义歧义与冗余，让所有导出 JSON 与前端渲染一致、可信。

### 1.1 统一动态/运输能力标志位（单一权威源）
- 改动：`benchmarks/attach_stage8.m`、`llmaoo.m`、`exports/export_result_json.m`、`viz/dashboard.py`。
- 做法：在 `attach_stage8` 中据 `cfg.AOO_DYNAMIC` / `cfg.AOO_AGV` 显式设置 `prob.AOO_DYNAMIC` / `prob.AOO_AGV`（目前 `attach_stage8` 不设 `has_dynamic`，仅 `define_problem` 设）。`export_result_json` 与 dashboard 一律读 `prob.AOO_DYNAMIC`/`prob.AOO_AGV`，废弃 `prob.has_dynamic`/`prob.has_agv` 作为导出/渲染判断（保留字段但标注 deprecated，或改由 `attach_stage8` 据 cfg 同步赋值）。
- 验证：`tests/run_all.m` 门禁 [9]（stageA）扩一个断言：`attach_stage8(prob,cfg_dyn).AOO_DYNAMIC == cfg.AOO_DYNAMIC`。

### 1.2 清理 Pareto 冗余字段
- 改动：`exports/export_result_json.m`。
- 做法：导出端只保留 `pareto.mk`（真实）、`pareto.lb`（真实）、`pareto.obj3`（三列：[mk_n, ld_n, en]）。删除 `pareto.Z` / `pareto.mk_n` / `pareto.lb_n`（与 obj3 前两列完全重叠）。前端 `make_pareto_figure` 已从 `obj3[:,2]` 取 energy，无需 mk_n/lb_n。
- 验证：`stageF_run` 重新导出后 `dashboard` Pareto 标签页渲染无 KeyError（py_compile + 探针）。

### 1.3 统一 Overview / 卡片的"final_best"语义
- 改动：`viz/dashboard.py` 的 `summary_cards` 与 `make_overview_table`。
- 做法：卡片与 Overview 表的 `final_best` 改为真实 `makespan`（已可用），或在仍显示归一化末值时显式标注"（normalized objective，非 makespan）"。推荐直接用真实 `makespan`，避免双语义误导。

### 1.4 数字孪生 3D 作业分层
- 改动：`viz/digital_twin.py` 的 `build_html` / `build_html_from_replay`。
- 做法：把 Z 轴从恒 0 改为 `((o.job-1) % nJob) * laneDepth` 的真实分层（当前 `((o.job-1)%nJob)*0.0` 是笔误），让多作业在 Z 方向分泳道，提升可读性。

### 1.5 收敛 ±std 带数据源对齐
- 改动：`exports/export_result_json.m` 或 `stageF_run`/`experiment_runs`。
- 做法：在 `experiment_runs`（N 次独立 run）中额外导出 `*_conv_<k>.json`（复用同一导出契约，仅含收敛轨迹），或在 dashboard 收敛标签页回退为单文件 `trace_makespan`（已支持）。确保默认导出下收敛页不出现空 std 带误导。

### 1.6 重导出投稿主结果
- 改动：用当前代码重新生成 `results/tevc_submission/tevc_full_result.json`（真实 mk/lb + mk_ub），替换 2026-08-14 的归一化旧文件，避免论文插图与正文语义脱节。

交付物：存储契约 v1.1（单一权威标志位 + 精简 Pareto）、前端渲染一致、`tevc_submission` 刷新。

---

## 阶段二：多目标建模 honest positioning（核心 novelty，3–5 天）

目标：解决评审"伪三目标 / 主链加权和"硬伤，给出可被审稿接受的多目标立场。

### 2.1 决定多目标立场（论文层，先于代码）
- 选项 A（推荐，投稿风险最低）：诚实定位为"LLM 引导的加权和自适应搜索"，把 NSGA-III 作为"附加的多目标分析视角"明确标注，不在主链声称 Pareto 优化。
- 选项 B（冲击更高 novelty）：把默认主链升级为真实 NSGA-III 支配排序（参考 `aoo_engine` 已有的 `nsga3_select` 分支），让 energy 真正参与选择。
- 建议：先走 A 完成投稿闭环；若审稿要求更强多目标 rigor，再升级到 B（代码分支已就绪，主要是把 `AOO_THREE_OBJ` 默认打开并补门禁 [6] 的三目标表述）。

### 2.2 修复三目标 energy 第三维退化（若选 B 或保留三目标存档）
- 根因：主链加权和 `w=[1,1,0]`（energy 权重恒 0），energy 不参与选择；且 `machW` 全 1 使 `energy=处理时间`，前沿解收敛到同一常数。
- 改动：`evaluate.m`（`w3` 不再恒 0，由 cfg 注入 `W_ENERGY`）、`llmaoo_config.m`（增 `W_ENERGY` 默认 0 保零回归；三目标模式 `AOO_THREE_OBJ=true` 时置合理值如 1.0）、`attach_stage8`/`define_problem` 的 energy 构造支持非零权重。
- 验证：`quality_metrics`（门禁 [10]）检查 HV/IGD 的 energy 维度方差 > 0；`stageA` 自测断言 `pareto.energy` 非恒定。

### 2.3 门禁 [6] 补三目标竞争力表述
- 改动：`gate_competitiveness.m` 增加三目标分支入口（`AOO_THREE_OBJ=true` 时跑 NSGA-III 主选 vs Random 的非支配前沿比较，用 HV 而非加权和），确保启用 NSGA-III 主选后竞争力证据与多目标主张一致。

### 2.4 论文措辞与图表一致性
- 明确图注："weighted-sum adaptive search (main) + NSGA-III analysis (supplementary)"，避免审稿人将主链误读为 Pareto 优化。

交付物：多目标立场决策文档 + （若 B）真实 NSGA-III 主链 + energy 维度有效分化 + 门禁 [6] 三目标版。

---

## 阶段三：真实证据链补全（实验长跑，2–4 天 + 计算时间）

目标：补齐 novelty 与竞争力的量化证据。实验脚手架已具备，**本阶段主要是"跑 + 联网 Key"**。

### 3.1 大实例 SOTA 补全（解决 MK02/03/06 gap +57%~+104%）
- 脚本：`tests/stage7_run.m`（MK01-10 N=30 + 多实例 aoo/ga/pso/alns/random + Wilcoxon）已就绪；`tevc_sota.m`（N=30 完整基准 + 7 方对比）已就绪。
- 数据依赖：MK02–10 标准 `.fjs` 需置于 `data/`（部分已存在，见 `data/` 目录 10 个 .fjs）。
- 执行：`_cc_stage7.bat` / `tevc_sota.m`，长跑约 30–60 分钟。
- 产出：`logs/stage5_sota_compare.json`、完整 MK01-10 表图。

### 3.2 联网 LLM 真实增益量化（解决"增益=0"证据缺口）
- 脚本：`tevc_llm_gain.m` 三臂（aoo / modulate / full）+ 难实例 MK04/06/09 + dynamic + multi + Wilcoxon，已就绪。
- 前提：设置环境变量 `DEEPSEEK_API_KEY`（联网），`LLM_ENABLE` 自动 true；否则 `full` 退回 mock 仍得 0（与阶段 D 一致）。
- 执行：`_cc_tevc_gain.bat`（若存在）或 `tevc_llm_gain()`。
- 产出：`logs/tevc_llm_gain.json`。若联网仍不可达，诚实记录"离线 modulate 增益"并调整论文 novelty 主张为"结构化调制"而非"联网 LLM"。

### 3.3 统计显著性收口
- `tests/stat_report.m`（Wilcoxon + effect size）已就绪，确保每个对比表附 p 值与效应量。

交付物：完整 MK01-10 SOTA 表 + 难实例三臂 LLM 增益（含联网 full）+ 显著性报告。

---

## 阶段四：投稿级收口与评审自检（1–2 天）

目标：确保前述改动零回归、文档一致、可复现。

### 4.1 回归门禁全绿
- 执行：`tests/run_all.m`（[1]–[18] 全绿）；重点确认门禁 [8]（stage9 导出契约）、[9]（stageA 标志位）、[10]（quality_metrics）、[16]（最火场景 gate）覆盖阶段一/二改动。
- 阶段一/二每改一处，立即跑对应门禁，避免回归累积。

### 4.2 可复现性强化
- `cfg_hash` 当前 8 位 FNV-1a 对小扰动碰撞未量化；建议在哈希字符串中追加 `AOO_THREE_OBJ`/`OFFLINE_STRUCTURED_MODULATE`/`W_ENERGY` 等可读开关，便于人工溯源 JSON 到配置。

### 4.3 文档对齐
- 刷新 `results/INDEX.md` 与子目录 README 的字段表（标注量纲：sum load vs unbalance=max-min；normalized vs raw）。
- 更新 `MEMORY.md` 阶段演进与遗留项，标注本方案完成后关闭的条目。

### 4.4 投稿包自检清单
- [ ] 多目标立场声明与图表一致（阶段二）
- [ ] MK01-10 SOTA 表 + 显著性（阶段三.1）
- [ ] LLM 增益三臂证据（阶段三.2，注明联网/离线）
- [ ] 所有插图来自当前代码导出（非 2026-08-14 旧归一化 JSON）
- [ ] 回归全绿 + NaN/Inf=0

---

## 优先级与里程碑

| 优先级 | 阶段 | 风险 | 收益 | 前置 |
|---|---|---|---|---|
| P0 | 阶段一（1.1/1.2/1.3/1.6） | 低 | 高（消除误导性契约，投稿前必做） | 无 |
| P0 | 阶段三.1（大实例 SOTA） | 低（脚本就绪） | 高（竞争力硬门槛） | data/*.fjs 齐备 |
| P1 | 阶段二（多目标立场 + energy 修复） | 中（若选 B 涉及主链） | 高（novelty 核心） | 阶段一定稿 |
| P1 | 阶段三.2（联网 LLM 增益） | 中（依赖网络/Key） | 高（novelty 证据） | DEEPSEEK_API_KEY |
| P2 | 阶段一.4/1.5（3D 分层 / std 带） | 低 | 中（可读性） | 阶段一基础 |
| P2 | 阶段四（收口） | 低 | 高（投稿安全网） | 阶段一–三 |

建议执行顺序：阶段一（P0）→ 阶段三.1（P0，可并行长跑）→ 阶段二（P1）→ 阶段三.2（P1）→ 阶段四（P2 收口）。阶段三.1 的长跑可在阶段一合并后立即后台启动，与其他阶段并行。

## 关键约束与提示
- 所有改动须保持 `AOO_DEFAULT_SCENARIO='static'` 默认零回归（门禁 [9] 守护）。
- 不要重写大文件；用 `replace_in_file` 定点修改（如 `attach_stage8`、`export_result_json`、`dashboard.py`）。
- 实验长跑用独立日志文件名（避免残留 matlab.exe 占用，参见 MATLAB 运行坑）。
- 联网增益若环境不可达，不要伪造数据，改为诚实定位 novelty 为"结构化 LLM 调制"。
