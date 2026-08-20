# FJSP LLMAOO 求解器项目评审报告（问题侧 / 方案侧 / 可视化与存储）

## Executive Summary

本项目是一个融合 LLM(DeepSeek)契约解析与自适应算子优化(AOO)双引擎的柔性作业车间调度(FJSP)求解器，实验脚手架与可视化链路已较为完整，门禁全绿、离线可跑、标准基准证据链已落地。但作为面向 IEEE TEVC 的投稿级工作，它在"问题侧"存在目标建模不诚实（默认加权和单目标却常以多目标叙事）、energy 第三维恒为 0.6645 塌缩（伪三目标）、动态/绿色场景多为演示而非主链三大硬伤；"方案侧"LLM 增益在离线缺 Key 时恒为 1.0（联网增益未量化即等于未验证）、未消费契约字段与死代码残留；"可视化与存储"已修复大部分历史问题（final_best 真实化、Z 轴分层、Pareto 冗余删除、标志位统一），但 `tevc_submission` 仍缺 `contract_version` 字段会触发 dashboard 误告警，且 energy 塌缩使 Pareto 色轴失效、`EXPORT_CONV_JSON` 默认关闭导致收敛 std 带默认不可用。整体结论：工程完成度高，但投稿前必须补强多目标诚实定位与联网 LLM 增益的量化证据。

## 一、问题侧评价（Problem Formulation）

### 1. 场景覆盖广，但动态/绿色多为"开关演示"而非主链能力

`define_problem.m` 统一定义了 static / green / multi / transport / dynamic / full 六种场景，目标涵盖 makespan、机器负荷不均衡度、能耗三类，并有 `data/MK01.fjs`~`MK10.fjs` 标准 Brandimarte 实例支撑。覆盖度在 FJSP 文献中属于中上水平。

但核查发现动态场景的实质能力不足：`dynamic_replay.m` 自述为"轻量结构性 demo"，主搜索循环 `aoo_engine.m` 中并无事件驱动的再调度内循环；`AOO_DYNAMIC=true` 仅触发离线回放导出（`attach_stage8.m` 提供能力位，`llmaoo.m` 兜底）。这意味着"动态重调度"在论文叙事中极易被审稿人要求复现真实机器故障/急件插入场景，而当前代码仅能产出演示性 replay 帧，不具备在线重调度主链。同样 `transport` 场景依赖 `has_agv` 但主解码 `decode.m` 未接入 AGV 运输时间，`parse_contract.m` 的 `dynamic_strategy`/`priority` 字段明确标注【当前版本未消费】。

### 2. 默认加权和单目标，与多目标叙事存在错位

`llmaoo_config.m:166-167` 默认 `W_MAKESPAN=1.0, W_LOAD=1.0`，适应度 `Z = w_mk*mk_n + w_ld*ld_n` 是加权归一化单目标。真正的 NSGA-III 非支配排序仅在 `AOO_THREE_OBJ=true` 时启用（`aoo_engine.m:130-147`），且该开关默认关闭（零回归设计）。`evaluate_population.m:42-47` 仅在 `AOO_THREE_OBJ && isfield(cfg,'W_ENERGY')` 时传入三元权重，否则回退二元。

问题在于：项目多处文档与可视化（Pareto 图、NSGA-III 质量指标 HV/IGD）以多目标方法呈现，但默认运行路径是单目标加权和。这是"方法定位不诚实"风险的核心来源，投稿时要么诚实定位为"LLM 引导的加权和自适应搜索（NSGA-III 作附加分析）"，要么将 NSGA-III 升级为主选并补三目标实验。

### 3. energy 第三维恒为 0.664495114 塌缩（伪三目标硬伤）

这是问题侧最需修正的定量缺陷。搜索 `results/tevc_submission/tevc_multi_result.json` 等文件，energy 第三维出现 1873+ 处，几乎全部等于 `0.66449511400651462`，仅个别点微扰到 `0.6644518`。根因链已查清：`llmaoo_config.m:44` 默认 `W_ENERGY=0`，`evaluate.m:48` 硬编码 `w3=0`，energy 不参与主链加权和，仅进入 `extra.obj` 作展示。即使 `aoo_engine.m:142` 已修为传 `[1 1 1]` 触发三目标分支、`evaluate_population.m` 已接 `W_ENERGY`，只要权重为 0 且 `compute_energy` 依赖 `prob.machW`，在 `machW` 全 1 时 energy 退化为处理时间常数，归一化后塌缩为定点值。结果：Pareto 散点第三维无分化，色轴失效，NSGA-III 实际退化为"伪三目标"。`multi` 场景 `AOO_THREE_OBJ=true` 却无能量分化，是投稿级硬伤。

## 二、方案侧评价（Solver / Approach）

### 1. AOO 五策略双引擎机制成立，自适应逻辑自洽

`aoo_engine.m` 的五策略（风=精英离散变异、水=POX 差分交叉、动物=复制精英前缀、滚动=Lévy 块反转、弹射=重置逃离）与三次衰减系数 `c=1-(t/T)^3`（`aoo_engine.m:13`）构成合理探索-利用平衡。停滞计数 `stag`/`elite_stag` 触发 LLM 调制与重启（`AOO_RESTART_PATIENCE`），局部搜索 `llm_guided_local_search.m` 已用 `sched(tt).op` 修正历史 `opOf` 索引错位（`llm_guided_local_search.m:36`）。历史 `opOf(t)` 误用现已规避：`decode.m:190` 的 `active_postprocess` 由 `AOO_ACTIVE_DECODE`（默认 false）控制，`ga_fjsp`/`pso_fjsp` 越界崩溃已在 2026-08-17 修复。标准基准证据链（`logs/stage7_benchmark.json` 7/10 达 BKS、`logs/stage7_sota.json` 真实 Wilcoxon p<0.001）扎实，AOO 相对 ga/pso/alns/random 统计显著占优，这是方案侧最有力的投稿支撑。

### 2. LLM 增益在离线缺 Key 时恒为 1.0，联网增益未量化

`deepseek_chat.m` 在无 API Key 时返回默认增益=1.0，`ablation.m` 诚实声明离线 `full≡modulate`。但这意味着"联网 LLM 增益"这一核心 novelty 当前实测为 0（网络不可达），`tevc_llm_gain.m` 三臂实验需 `DEEPSEEK_API_KEY`+网络方可写入论文。当前所有实验均在离线降级下完成，LLM 的实际贡献（相对纯 AOO 调制）尚无量化证据。阶段三.2 仍被此阻塞，是方案侧最大的"未验证 novelty"风险。

### 3. 死代码与未消费字段残留

`nsga3_core.m`、`diag_buildpareto.m`、`verify_viz_multi.m` 仍为 0 字节空文件；`parse_contract.m` 的 `dynamic_strategy`/`priority` 字段标注未消费；`obj_eval.m`/`obj_of.m` 为旧评估入口已被 `evaluate` 取代但仍在仓库。文档称"AOO 五策略"，`llmaoo.m:7` 注释却写"六阶段生物启发"，阶段计数表述不一致。这些不影响运行，但投稿代码审计时应清理以降低审稿疑虑。

## 三、可视化设计评价

可视化链路（`viz/` 三件套 + Streamlit dashboard + Three.js 数字孪生）已完成度较高，历史问题大部分已修复：

- `dashboard.py:444/558` 的 Overview/卡片 `final_best` 已统一为真实 makespan（不再用 `trace_best` 归一化末值）。
- `digital_twin.py:200` Z 轴已改为按 job 真实分层（旧 `*0.0` 笔误已修，`figures/digital_twin.html` 可正确三维分层）。
- Pareto 冗余 `Z/mk_n/lb_n` 已删（`export_result_json.m:78`、aoo_engine:271-272），`build_pareto` 仅留 `mk/lb/energy/obj3`。
- 标志位分裂基本同步：`attach_stage8.m:60-67` 将 `cfg.AOO_DYNAMIC` 同步到 `prob.AOO_DYNAMIC` 与 `prob.has_dynamic`。

但仍存在问题：

1. **`tevc_submission` 缺 `contract_version` 字段**：`tevc_full_result.json`/`tevc_multi_result.json` 顶层仅 `version="1.0"`，无 `contract_version:'1.1'`，会触发 `dashboard.py:604` 的"legacy/normalized format"误告警，与文件实际已是真实刻度（mk=34/35）矛盾。应补字段或重导出。

2. **energy 塌缩使 Pareto 色轴失效**：上一节所述 energy 恒 0.6645，导致 NSGA-III Pareto 第三维无视觉分化，dashboard Pareto Tab 与 `figures/convergence.html` 的色彩映射失去意义。可视化本身正确，但源数据缺陷使其失效。

3. **`EXPORT_CONV_JSON` 默认 false**（`llmaoo_config.m:66`）：`export_result_json` 默认不产生 `*_conv_*.json`，dashboard 收敛页的 ±std 带依赖独立 run 导出（`dashboard.py:639-640` 回退匹配），默认导出下 std 带为空。收敛方差分析在默认 pipeline 不可用，与 dashboard 收敛页预期不一致。

4. **0 字节占位文件与覆盖风险**：`figures/gantt__demo.html`、`replay__demo.html`、`convergence__demo.html`、`tevc_p0verify_result.json`(0B) 等空壳易被 `discover_results()` 误扫；`stageF`/`hot` 脚本用固定 stem（`stageF_conv_%d.json`）多次运行静默覆盖旧收敛文件。

## 四、结果存储/JSON 契约评价

`export_result_json.m` 已采用 struct array 直出扁平数组、`schedule` 用 cell-of-row 避免 `jsonencode` 双嵌套，字段含 `makespan/loadUnb/mk_ub/cfg_hash/seed/scenario/trace_makespan(真实)/pareto` 等，契约规范度良好。但：

1. **`trace_best` 双语义残留**：`export_result_json.m:66` 仍保留 `trace_best`（归一化加权和末值）作"兼容"，前端多处 fallback 读它。虽 dashboard 已优先 `trace_makespan`，但同页存在归一化与真实双刻度语义，误读风险仍在，建议删除或显式标注。

2. **投稿主结果 JSON 须重导出**：`results/tevc_submission/` 中 energy 维塌缩、缺 `contract_version`，建议用当前代码统一重导出全部 tevc_* JSON，使 Pareto 真实分化且契约版本一致。

3. **字段命名一致性**：`loadUnb`/`loadUnb` vs `lb`/`loadVec` 命名风格不统一（驼峰与缩写混用），跨 JSON 与 Python 解析时易错，建议统一命名规范。

## 五、综合结论与优先修复项

项目工程化完成度高、实验证据链扎实、离线可复现，具备投稿基础。投稿前按优先级：

- **P0（硬伤）**：修复 energy 第三维塌缩——将 `W_ENERGY` 设为非零并修正 `evaluate.m:48` 硬编码 `w3=0`，使 NSGA-III 三目标真实生效；用当前代码重导出 `tevc_submission` 全部 JSON 并补 `contract_version`。
- **P1（诚实定位）**：明确方法定位（加权和自适应搜索 vs 真 NSGA-III 主选），对应补充三目标实验与 Wilcoxon；量化联网 LLM 增益（需 DEEPSEEK_API_KEY+网络复跑 `tevc_llm_gain`）。
- **P2（整洁度）**：删除 0 字节死文件、未消费契约字段、旧评估入口；统一 `trace_best` 语义或删除；默认开启 `EXPORT_CONV_JSON` 或文档说明 std 带依赖。
- **未来工作（诚实讨论）**：MK02/MK06/MK09 大/难实例 AOO 偏弱（分别 +26.9%/+65.5%/+7.7%）；动态/transport 场景升级为主链能力。

## References

1. [FJSP LLMAOO 项目根目录](c:\Users\Joyce_SUN\Desktop\FJSP)
2. [aoo_engine.m 核心引擎](c:\Users\Joyce_SUN\Desktop\FJSP\aoo_engine.m)
3. [llmaoo_config.m 配置](c:\Users\Joyce_SUN\Desktop\FJSP\llmaoo_config.m)
4. [define_problem.m 问题定义](c:\Users\Joyce_SUN\Desktop\FJSP\define_problem.m)
5. [evaluate.m 多目标评估](c:\Users\Joyce_SUN\Desktop\FJSP\evaluate.m)
6. [export_result_json.m 存储契约](c:\Users\Joyce_SUN\Desktop\FJSP\exports\export_result_json.m)
7. [dashboard.py 可视化](c:\Users\Joyce_SUN\Desktop\FJSP\viz\dashboard.py)
8. [tevc_submission 投稿结果](c:\Users\Joyce_SUN\Desktop\FJSP\results\tevc_submission\tevc_multi_result.json)
9. [stage7_sota.json AOO vs 基线 Wilcoxon](c:\Users\Joyce_SUN\Desktop\FJSP\logs\stage7_sota.json)
