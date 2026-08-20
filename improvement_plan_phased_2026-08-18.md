# FJSP-LLMAOO 阶段性改进方案（2026-08-18）

基于 `research_report_project_review_current_2026_08_18.md` 的评审结论制定。所有阶段遵循既有"零回归 / ADDITIVE / 离线可跑"纪律：改动 solver 数值须配门禁；契约改动须带 `contract_version`；联网行为须由 `DEEPSEEK_API_KEY` + 网络可达显式触发。

优先级定义：
- **P0**：投稿阻塞项（不解决则论文核心主张站不住）。
- **P1**：证据链补强与诚实定位（显著提升录用概率）。
- **P2**：设计负债清理与可复现性增强（降低审稿人挑刺面，非阻塞）。

---

## 阶段一 P0：方法学诚实定位 + 大实例信誉缺口

**目标**：消除"默认两目标加权和主链"与"NSGA-III 三目标主选"混述；对 MK02/06/09 偏弱给出可接受的投稿姿态。

### 任务 1.1 — 论文/README 方法学口径统一
- 在 README 与投稿文档中明确：默认路径（`AOO_THREE_OBJ=false`）是"LLM 引导的两目标加权和自适应搜索"；投稿多目标路径（开关 `true`）是 NSGA-III 真实三目标主选。二者为互斥配置，不得混述为单一方法。
- 在 `llmaoo_config.m` 顶部契约注释中补充此区分（已在 README L4-8 部分体现，需同步到代码注释）。
- 验收：README + 配置注释口径一致；无"主链是加权和但论文称多目标"的隐含矛盾。

### 任务 1.2 — 大实例的稳健补偿探索（替换不可靠的纯调参）
- 现状：`stage7_strong_x3.m` 仅调 `LS_KMAX`/`AOO_REFINE_EVERY` 运行时参数，结论不可靠（激进版 MK02 改善但保守版退化）。
- 动作：放弃"调参假装改善"。改为两种可接受姿态择一：
  - **(a) 诚实 Limitations**：保留默认配置主证据（7/10 达 BKS），在论文 Limitations 明确 MK02/06/09 偏弱，附 `logs/stage7_benchmark.json` 真实 gap 数据；
  - **(b) 结构性补偿**（若时间允许）：针对大实例增大预算（POP/MAXGEN 自适应按 nOp 缩放）或启用"多起点重启 + 更长 refine"，作为可复现的"large-scale 配置"，与默认配置分开报告，避免污染 7/10 主证据。
- 验收：若选 (b)，新增 `tests/stage7_large_config.m`（零源改动，仅运行时配置 + 独立日志 `logs/stage7_large.json`），并在 run_all 加门禁断言 large-config 在 MK02/06/09 上 gap 不劣于默认配置；若选 (a)，提交 Limitations 段落草稿与数据表。

### 任务 1.3 — 阶段四实证全绿复跑（已 2026-08-18 完成，维持）
- 维持 `tests.run_all` [1]-[18] ALL GREEN 作为每次改动的回归门禁。任何 P0/P1 源改动后必须重跑 `_cc_stage4_runall.bat`。

---

## 阶段二 P1：联网 LLM 真实增益证据链

**目标**：补齐 novely 核心（"LLM 引导"）的量化证据，或固化诚实代理声明。

### 任务 2.1 — 联网增益复跑通道验证
- 现状：`tevc_llm_gain.m` 健全、`experiment_runs` 三臂（`aoo`/`modulate`/`full`）分发逻辑透明，`full` 仅在 `DEEPSEEK_API_KEY` 非空时 `LLM_ENABLE=true` 真实联网，否则 `full≡modulate`。当前环境离线，`results/tevc_llm_gain/tevc_llm_gain.json` 是诚实降级产物。
- 动作：注入 `DEEPSEEK_API_KEY` 并确认 `api.deepseek.com` 可达后，跑 `tests.tevc_llm_gain`（5 场景 × 3 臂 × N=30 × MAXGEN=130）。
- 验收：`tevc_llm_gain.json` 出现 `full` 与 `modulate` 可区分结果；`online_llm_modulate` 真实增益（diff）非零且经 signrank/Wilcoxon 检验；`env_manifest.json` 更新为"online"态。

### 任务 2.2 — 增益归因可视化与可读报告
- 用 `make_figures.py` / `plotly_convergence.py` 生成三臂对比图（aoo vs modulate vs full 的 makespan 收敛与最终 gap），输出 `figures/llm_gain_*`。
- 验收：有可直接入论文的对比图 + 统计显著性表（p 值）。

### 任务 2.3 — 离线诚实代理的论文表述
- 若 2.1 仍因环境阻塞无法复跑，则在论文固化"离线结构化调制（`offline_structured_modulate`）是可复现代理"表述，并在实验章明确声明未宣称在线 LLM 量化增益（沿用 `env_manifest` 边界）。
- 验收：论文实验章有显式诚实声明段，不与事实冲突。

---

## 阶段三 P1：三目标主选的 SOTA 竞争力证据

**目标**：让 NSGA-III 主选路径也有独立的竞争力证据，与两目标门禁 [6] 口径对齐。

### 任务 3.1 — 三目标 SOTA 对比脚本
- 现状：门禁 [6] 仅两目标 AOO vs Random（p=0.5648 不显著劣化）；门禁 [9]/[10] 仅验证 energy 分化与 HV/IGD 有限非负，未做多算法对比。
- 动作：新增 `tests/stageB_sota.m`（或扩展 `stage7_sota_only`）：在 `multi` 场景下跑 AOO(NSGA-III) vs GA/PSO/ALNS/Random 三目标，记录 HV/IGD/PF-size，做 Kruskal-Wallis + 事后检验。
- 验收：产出 `logs/stageB_sota.json`（三目标 HV/IGD 对比 + p 值）；run_all 加门禁 [19] 断言 AOO 三目标 HV 不显著劣于最佳 baseline（p>0.05 或显著优于多数）。

### 任务 3.2 — 三目标门禁 [6] 升级
- 将 competitiveness 门禁升级为"两目标与三目标双路径均报告竞争力"，避免口径不一致。
- 验收：run_all 输出中三目标竞争力结论明确。

---

## 阶段四 P2：结果存储契约清理（obj3 冗余与语义脆弱）

**目标**：消除 `pareto` 中 `mk/lb` 与 `obj3` 前两列的冗余双表达，明确 energy 色轴来源。

### 任务 4.1 — Pareto 契约精简（向后兼容）
- 现状：`pareto = {mk, lb, obj3(:,3 列=[mk_n,ld_n,en_n]), energy}`。obj3 前两列与 mk/lb 重复；两目标分支 obj3 第三列恒 NaN 易误读。
- 方案 A（推荐，最小改动）：保留 `mk/lb`（真实刻度，Pareto 坐标轴）与新增 `energy_n`（仅归一化 energy，作色轴）；**删除 `obj3` 字段**（NSGA-III 内部 `pf3` 仍用三向量，仅导出端不再写冗余 obj3）。前端 `make_pareto_figure` 改为读 `pareto.energy_n` 作色轴，`has_energy = isfield(p,'energy_n')`。
- 方案 B（零契约改动）：保留 obj3，但在 export_result_json 注释 + README 明确声明 "obj3 前两列 == mk/lb 的归一化形式（NSGA-III 输入向量），仅第三列 energy 用于色轴"，并在 dashboard 加断言防止误用。
- 验收：导出 JSON 抽样确认无冗余（方案 A 下 `obj3` 消失、`energy_n` 出现）；dashboard Pareto 色轴正常；旧 `<1.1` 契约告警仍生效；`contract_version` 升到 `1.2` 并写入 README 契约段。

### 任务 4.2 — 两目标分支语义澄清
- 在两目标分支导出 `energy_n = []`（空数组）而非 NaN 列，前端据此明确标 "[2-obj]"（已实现标题逻辑，仅需契约字段对齐）。

---

## 阶段五 P2：可复现性与可视化增强

### 任务 5.1 — std 带默认可用性
- 现状：`EXPORT_CONV_JSON` 默认 false，std 带不可用（零回归安全默认）。
- 动作：为投稿图提供"批量导出脚本" `_cc_conv_batch.bat`（显式置 `EXPORT_CONV_JSON=true` 跑 N 次），输出 `logs/conv_*.json`，再由 `plotly_convergence.py` 聚合 mean±std。不改动默认 false。
- 验收：有可复现的 std 带生成命令与示例图。

### 任务 5.2 — 数字孪生/回放契约对称性核对
- 现状：`export_replay_json` 已置 `kind='dynamic_replay'`，`digital_twin.py` 兼容 `kind` 与 `frames` 双入口——已对称。仅补充单测断言：replay JSON 必含 `kind` + 非空 `frames`。
- 验收：run_all 加门禁断言 replay 契约完整性。

### 任务 5.3 — README 阶段表同步
- 每次阶段完成同步 README "阶段演进与状态" 表与 "已知阻塞/待补" 段，保持文档与代码零偏差（历史多次出现文档滞后）。

---

## 执行顺序与里程碑

| 顺序 | 阶段 | 优先级 | 阻塞投稿？ | 预计工作量 |
|------|------|--------|-----------|-----------|
| 1 | 阶段一（1.1+1.2+1.3） | P0 | 是 | 中（文档+探索脚本） |
| 2 | 阶段三（3.1+3.2） | P1 | 否（但强烈建议） | 中（新 SOTA 脚本+门禁） |
| 3 | 阶段二（2.1+2.2+2.3） | P1 | 否（环境依赖） | 中（依赖 Key+网络） |
| 4 | 阶段四（4.1+4.2） | P2 | 否 | 小（契约+前端对齐） |
| 5 | 阶段五（5.1+5.2+5.3） | P2 | 否 | 小 |

**里程碑 M1（投稿前置）**：完成阶段一 + 阶段三，使方法学口径与多目标竞争力证据齐备。
**里程碑 M2（证据完整）**：完成阶段二（联网增益或诚实固化）。
**里程碑 M3（打磨）**：完成阶段四 + 阶段五，消除设计负债。

## 关键约束（贯穿所有阶段）
- 任何 solver 数值改动必须配 run_all 门禁 [1]-[18]（及新增 [19]）全绿。
- 契约改动必须升 `contract_version` 并保留旧契约告警，避免破坏历史导出。
- 联网行为仅由 `DEEPSEEK_API_KEY` 非空触发；离线态不伪造增益。
- 不 taskkill、不擅自启动进程、优先独立日志避免占用冲突（用户安全偏好）。
