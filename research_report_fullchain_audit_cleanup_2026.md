# FJSP LLMAOO 全链路审计 + 清理 + 结果整理报告（2026-08-14）

## 摘要
按用户要求，对 FJSP LLMAOO 求解器做了三项工作：① 全链路审计（核心模块设计、双引擎是否真发挥作用、有无死锁/暗伤/弊病）；② 清理无用文件；③ 整理全部保存结果。审计结论：LLM 与 AOO 双引擎链路通畅、无死锁、无 NaN/Inf 泄漏，但发现并修复了一个重大结构暗伤——LLM 三增益之一的 `explore_bias` 从未被任何搜索算子消费（实为死参数）。修复后回归套件 18 步全部 PASS。清理把 175 个冗余/过时文件移入 `archive/`（可回收，非删除）；真实结果按 13 个场景归入 `results/` 并附导航索引。

## 一、全链路审计结论

### 1.1 双引擎协同链路（通畅，无死锁）
链路为：`llmaoo` 主入口 → `llm_hook`（每 `LLM_CALL_EVERY_GEN`/`LLM_DIAG_EVERY_GEN` 代触发）→ `deepseek_chat`（联网/离线降级）→ `parse_contract` → `make_llm_state` / `offline_structured_modulate` / `online_llm_modulate` → 生成 `llm_state{levy_gain, diff_gain, explore_bias, last_best}` → `aoo_engine` 每代 `aoo_params(t,T,N,nOp,llm_state)` 消费增益调制算子强度，并经 `on_iter` 回调把下一代调制状态回灌。

关键正确性核实：
- `llm_state` 以值传递进入 `aoo_engine`，但 `on_iter` 返回的 `ns` 在 L196 被重新赋值回 `aoo_engine` 的局部 `llm_state`，因此 `levy_gain`/`diff_gain`/`explore_bias` 的调制**确实逐代传播**（非一次性）。
- `last_best` 停滞门控在 `llm_hook` 内通过 `llm_state.last_best = best` 继承，跨代连续，无陈旧状态交叉污染（`default_llm_state` 每次 `llmaoo` 调用重置为 Inf）。
- 主循环设有 NaN/Inf 守卫（L165-168）：异常精英自动回退上一精英，冒烟与回归运行中 `nan_count=0`，无数值污染。
- 停滞重启（L148-162）与早停（L202-204）基于独立计数器（`elite_stag` vs `stag`），互不冲突，无死锁。

### 1.2 关键暗伤（已修复）：explore_bias 死参数
- **问题**：`llm_state` 三增益 `levy_gain`/`diff_gain`/`explore_bias` 中，`explore_bias` 被 `parse_contract` 解析、被 `make_llm_state`/`offline_structured_modulate` 赋值、被 `tests/stageC_run.m`/`stageD_run.m` 断言，但**从未被 `aoo_engine` 任何算子读取**。原风传播 `windPm = max(0.15*c + 0.02, ...)` 只用衰减系数 `c`，忽略 `explore_bias`。
- **影响**：LLM 名义上输出三增益，实际只有 `diff_gain`（缩放 animal_copy 的 `e`）与 `levy_gain`（缩放 rolling/ejection 的 Lévy）生效；五策略中"风传播"完全不受 LLM 调控，双引擎协同在维度上不完整（仅 2/5 策略真正响应 LLM）。
- **修复**：`aoo_engine.m` 风传播改为 `windPm = max(0.15*c*llm_state.explore_bias + 0.02, cfg.AOO_MIN_EXPLORE)`。修复后 LLM 三增益全部落实，覆盖风/动物/滚动/弹射四策略（水传播为差分交叉，强度由 `m`/`L` 经 `sqrt(N/nOp)` 缩放，设计上不接 LLM，可接受）。
- **验证**：修复后 `tests/run_all` 全 18 步 ALL GREEN（含不等工序实例鲁棒性单测 R1/R2 通过，opOf 误用未复发）；独立冒烟 `aoo_engine` MK01：`mk=37, lb=6, iters=30, nan=0`。

### 1.3 其余模块核实（CLEAN）
- `decode.m` / `evaluate.m` / `obj_of.m`：半主动解码、AGV 运输约束、归一化加权目标（以 `prob.mk_ub` 统一归一化，双目标均衡生效）正确；入口防御（长度/NaN/工件号）齐全。
- `critical_path.m` / `llm_guided_local_search.m`：`loc_of` 整数索引崩溃 bug 已于 2026-08-14 早次修复（`llm_gain_quant` 联网组），现鲁棒。
- `refine_elite` 关键路径邻域精炼：使用 `kk = sum(chrom.OS(1:t)==j)` 与 decode 一致，未误用固定 `opOf`。
- `active_postprocess`（L190 `prob.opOf(t)` 误用）：仅存在于默认关闭的 `AOO_ACTIVE_DECODE` 路径，零回归不受影响；若将来开启需改用 `kk=sum(OS(1:t)==j)`。
- `water_xover`：仅受 `m`/`L`（由 `min(1,sqrt(N/nOp))` 缩放）控制，不接 LLM。`diff_gain` 已覆盖 animal 传播，属可接受设计，非缺陷。
- 测试 `[6]` 竞争力门禁（AOO vs Random）有真实 Wilcoxon 断言；`[2]` decode_eval 206 PASS。

### 1.4 实测数值（证明引擎真发挥作用）
- 回归 MK01 AOO 最优 mk=34.0（BKS=40，gap=0）；stage5 七方 SOTA 比对 AOO/GA/PSO/Random 全跑通。
- 投稿主结果 `tevc_submission`：full(动态+绿色+AGV) mk=38.0、multi(三目标 NSGA-III) mk=38.0、HV=0.0007 IGD=0.2210 PF=719。
- 联网 LLM 增益量化（`llm_gain_quant`）：链路可用（online=40 次），但 MK01 加权和框架下增益=0（AOO 已收敛 plateau）；兑现 LLM 真实增益需在难实例/动态重调度/多目标框架（见 MEMORY 待补项）。

## 二、文件清理
- 工具：`_cleanup.py` / `_cleanup2.py`（保留可重跑）。
- 移入 `archive/`（可回收，非永久删除）：
  - 根目录调试脚手架：`_cc_dbg.bat`/`_dbg_*.bat`/`_diag*.bat`/`_diag*.log`/`_probe_streamlit.py`/`_v_visualize.txt`/`_dbg_*.py`/`_dbg_*.m`/`probe_*.m`/`_v_check.m`/`stageCdbg.m`/`stageCsmoke.m`/`run_all_A.m`/`run_all_B.m`/`cc_stageA.m`/`cc_stageB.m`/`_*.ps1` 等。
  - 重复 `run_2026-08-12/13_*.log` 调试日志与各类 `_*.log`/`_*.txt` 散件。
  - 过时文档：`research_report_fullchain_*.md`（多版 recheck）、`research_plan_*.md`、`improvement_plan_*.md`、`project_review_*.md`。
  - 噪音文档 `dual_engine_architecture.md`（描述的是另一个教育路径优化项目，与 FJSP 无关）。
  - 可疑 `edit_patent.py`（经核实会向专利书回填已删除的伪内容）、`build_patent.py`（其生成器）——非求解器组件，移出根目录。
- 根目录保留：全部核心求解器 `*.m`、场景 runner（`submit_tevc.m`/`hot_run_*.m`/`run_full_hot.m`/`llm_gain_quant.m`/`tevc_*.m`/`gen_mk01_mat.m`）、关键 `_cc_*.bat`、`tests/`、`benchmarks/`、`data/`、`viz/`、`figures/`、`MEMORY.md`、最终报告 `research_report_tevc_gap_closure.md`。

## 三、结果整理
- 真实求解产物按场景归入 `results/`，含 JSON 契约（schedule/makespan/loadVec/trace_best/pareto/problem）、收敛序列、回放、运行日志：
  - `tevc_submission/`（投稿主结果，最该优先看）
  - `hot_dynamic/` `hot_multi/` `hot_full/`（最火问题侧闭环）
  - `stageF_real/`（真实数据可视化闭环证据）
  - `stage5_benchmark/`（MK01-10 + 七方 SOTA 对比）
  - `stage8/` `stage9_export/`（模块自测）
  - `llm_gain_quant/` `tevc_llm_gain/` `tevc_sota/`（LLM 增益与 SOTA 实验）
  - `fullchain_demo/` `audit_smoke/` `regression/`（演示/审计/零回归）
- `results/README.md`：导航索引 + 使用建议。
- `viz/dashboard.py` 同步增强：`discover_results`/`discover_replays` 改为递归 + 扩展匹配 `tevc_*`/`hot_*`/`stageF_*`/`*_result.json`/`*_replay.json`，整理后仍能发现 60 个结果 + 10 个回放，且契约兼容（`tevc_full_result.json` 含完整字段）。`py_compile` 通过。

## 四、给用户下一步分析的建议
1. 看投稿证据链：先读 `research_report_tevc_gap_closure.md` + `results/tevc_submission/`。
2. 若要让 LLM 增益"可量化且显著"：在网络可达环境填 DeepSeek Key，对难实例 MK04/06/09（AOO 未完全收敛）跑 `tevc_llm_gain` N=30，并升级为 LLM4EO 式在线算子元进化（与 2026 文献 LLM4EO/LLMAGEO/DSevolve 同构）。
3. 完整 SOTA 表：触发 `tevc_sota`（已在后台跑过纯算法部分）或 `stage7_run` N=30 产出 MK01-10 完整表图。
4. 可视化复盘：`pip install -r viz/requirements.txt && streamlit run viz/dashboard.py`，Overview 标签页聚合全部 `results/` 下契约。

## 五、遗留事项（非阻断）
- `decode.m` active 解码路径 `opOf` 误用需在开启 `AOO_ACTIVE_DECODE` 前修（默认关，零回归）。
- `explore_bias` 接入后建议补一个定向单测（断言 windPm 随 explore_bias 变化），纳入 `tests/run_all`。
- 联网 LLM 真实增益仍待难实例量化（环境代理时通时断）。
