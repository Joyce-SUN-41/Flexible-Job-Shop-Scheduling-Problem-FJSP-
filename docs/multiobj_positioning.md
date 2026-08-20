# 阶段四收口：多目标立场诚实定位（Multi-Objective Positioning）

> 交付物类型：论文 novelty / 方法学口径定位声明（纯文档，零 solver 数值改动，零回归）。
> 决策依据：`improvement_plan_phased_2026_08_19.md` 阶段四 optA（推荐、低风险）。
> 关联代码事实：`llmaoo_config.m` L11-15、`aoo_engine.m` L38/130/239、`README.md` L3-8/L72-75、
> 门禁 [6]（默认两目标主链）+ [20]（NSGA-III 三目标路径）。

## 1. 代码现状（事实基线）

- 默认主链：`AOO_THREE_OBJ=false` → **两目标加权和自适应搜索**
  （`get_best → min(sum(Z,2))`，权重 `W_MAKESPAN`/`W_LOAD`），NSGA-III 仅当显式开启时作为
  三目标可选路径。该路径由 `aoo_engine.m` 真实实现（非伪多目标、非附加评估）：开启时
  NSGA-III 非支配排序 + 参考点小生境替主链选 N 个个体，`evaluate` 第五输出为三目标向量
  `[mk_n, ld_n, en_n]`，HV/IGD 由门禁 [10]（`quality_metrics`）端到端验证。
- 两种配置（`AOO_THREE_OBJ` 开关）**互斥**，不得混述；`cfg_hash` 已纳入该开关，确保实验可复现隔离。

## 2. 阶段四决策：optA（采纳），optB（显式不做）

- **optA（采纳，本文件即交付）**：维持默认两目标加权和主链不动，novelty 诚实定位为
  "LLM 引导的加权和自适应搜索 + 结构化知识调制（structured-knowledge modulation）"。
  NSGA-III 三目标作「可选扩展 / 对比」章节，由门禁 [20] 独立校验，不与默认主链证据混用。
- **optB（显式不做）**：不将 NSGA-III 设为主投稿主链路、不重写默认选择路径、不补门禁 [6]
  双口径重跑阶段二。理由（安全边界）：
  1. 改主链数值语义须全量重跑阶段二（MK01–10 N=30 + 五臂 SOTA），破坏已建立的默认两目标
     竞争力证据，违背"零回归边界"。
  2. 现有 `logs/stageB_sota.json` 实证（MK01 N=30）显示：AOO 三目标 HV 均值 0.0016 vs
     Random 0.0028，**Wilcoxon p=2.2e-6 (h=1) → AOO 三目标 HV 在平等预算下显著弱于 Random**；
     Kruskal-Wallis 五组 p=0.997 无组间差异。即三目标路径当前**并非竞争力卖点**，
     强行推为主链会弱化投稿证据，且与诚实原则相悖。
  3. 多目标严谨性缺口已由门禁 [20] + `docs/limitations_draft.md` 诚实补齐（作 Limitations
     诚实讨论），无需升级主链即可满足 TEVC 多目标 rigor 要求。

## 3. 论文 novelty 表述约束（必须遵循）

- 默认投稿主链的表述**仅**对应两目标加权和自适应搜索 + LLM 结构化调制；**不得**将
  "NSGA-III / 真实三目标 / Pareto 前沿"等属性归因于默认主链。
- 多目标内容（NSGA-III 三目标路径、HV/IGD 指标、三目标 SOTA 对比）**仅**出现在明确标注的
  「可选扩展 / 对比分析」章节，且须同步引用 `logs/stageB_sota.json` 的诚实结论
  （AOO 三目标 HV 显著弱于 Random，平等预算下），不得暗示其为默认主链能力或竞争力优势。
- 能耗第三维（`W_ENERGY>0` 且 `AOO_THREE_OBJ=true`）真实参与选择的事实可陈述，但须说明其
  默认 `W_ENERGY=0` 时主链为纯两目标、数值零回归，避免读者误判默认配置含能耗优化。

## 4. 验收对齐

- 论文 novelty 表述与代码默认路径（`AOO_THREE_OBJ=false` 两目标加权和）一致：✓（约束见第 3 节）
- 门禁 [6] / [20] 口径分离、互不阻塞：✓（[6] 校验默认两目标主链；[20] 独立校验 NSGA-III 三目标）
- 零 solver 数值改动、零回归：✓（本文件为纯文档；optB 未执行）

## 5. 遗留可选（不在本期范围）

若后续审稿/期刊要求"默认即真实多目标主解集"，再评估 optB，但须先：
(a) 修复 AOO 三目标 HV 弱于 Random 的根因（参考点分层数 `NSGA3_P`、选择压力、或混合
两目标精英引导）；(b) 全量重跑阶段二双口径；(c) 重新零回归门禁 [6]/[19]。
