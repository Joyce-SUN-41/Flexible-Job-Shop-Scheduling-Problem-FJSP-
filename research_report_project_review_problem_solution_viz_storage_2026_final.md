# FJSP-LLMAOO 项目评审（问题侧 / 方案侧 / 可视化与结果存储）

## Executive Summary

本项目是面向 IEEE TEVC 投稿的柔性作业车间调度（FJSP）求解器，核心设计为"LLM（DeepSeek）契约解析 + AOO（自适应算子优化）五策略双引擎"。经对 `evaluate.m`、`aoo_engine.m`、`decode.m`、`load_data.m`、`exports/*`、`viz/*`、`dashboard.py` 等核心文件的逐行核查，结论如下：工程纪律（零回归、ADDITIVE 可视化、离线降级、诚实声明）成熟且契约意识强；问题侧场景覆盖广、解码稳健；存储契约（v1.2）已修复旧版"归一化值冒充真实值"的主要误导，Pareto 与收敛曲线现在默认读真实刻度。但仍有三类需要正视的设计层面问题：(1) 主链仍是两目标加权和而非真多目标，且 loadUnb 归一化分母用 makespan 上界导致其有效权重被淹没；(2) 大实例（MK02/03/06/07/10）求解质量系统性偏弱，SOTA 对比表格是否成立存疑；(3) 联网 LLM 真实增益在难实例上仍未量化，"双引擎" novelty 证据链关键缺口未补。可视化其余设计健康；存储契约仅余少量冗余与字段语义易混的小修。

---

## 一、问题侧评价（Problem Formulation）

问题侧由 `load_data.m` / `benchmarks/load_benchmark.m` / `define_problem.m` / `decode.m` / `evaluate.m` 构成，支持 static / green / transport / multi / dynamic / full 六种场景，并能以两目标（makespan + 机器负荷不均衡）或三目标（加 energy）运行。

优点：场景抽象清晰，归一化与解码在单一入口集中处理；`decode.m` 的 semi-active 解码（含二分定位间隙插入、AGV 运输时间、可选 active 后处理）稳健，fail-fast 防御（非法工件号、NaN/Inf、长度错配）齐全；`load_benchmark.m` 同时兼容 FJSPLib/wrqccc 两种 `.fjs` layout 与内置 MK01，机器号 0-indexed 自动 +1 归一化；`mk_ub` 固定理论上界计算有正有限守卫。问题侧工程质量是投稿级的水准。

需要指出三个问题侧短板：

第一，多目标建模不够"真"。代码同时维护两目标与三目标分支并实现了 NSGA-III 质量指标（HV / IGD），但主求解默认 `AOO_THREE_OBJ=false`，主链把 makespan 与 loadUnb 用固定权重加和为单一标量（见 `aoo_engine.m` 的 `get_best` → `min(sum(Z,2))`），并非真正的 Pareto 优化。即论文若以"多目标 FJSP"为核心 novelty，审稿人会指出主链是加权和而非 NSGA-II/III 支配排序。NSGA-III 的 `pareto` 存档与指标只是"附加证据"（默认关），未进入默认选择算子。这是一个需要在论文定位上诚实抉择的点：要么升级真多目标主链，要么把 novelty 定位为"LLM 引导的加权和自适应搜索"。

第二，loadUnb 归一化的分母选择存在量纲缺陷（真实暗伤，需正视）。`evaluate.m` 第 31-32 行对 makespan 与 loadUnb 都用同一个 `mk_ub`（各工序最快工时之和，量级 ~200）做分母归一化。但 loadUnb = max(loadVec)-min(loadVec) 的物理量级仅 ~7（见 `llmaoo.m` 默认输出与导出 `loadUnb`）。于是 `ld = loadUnb / mk_ub ≈ 7/200 ≈ 0.035`，而 `mk = makespan / mk_ub ≈ 38/200 ≈ 0.19`。在 `W_MAKESPAN=W_LOAD=1.0` 的等权设置下，loadUnb 项的归一化数值仅是 makespan 项的约 1/5，加权后"双目标均衡"实质上仍由 makespan 主导，负荷均衡贡献被系统性压低。内存笔记 C1（`logs/loadunb_sensitivity.json`，W_LOAD=0 时 `ld_norm=0.1133`）也佐证归一化使负荷项贡献偏小。正确的做法应是 loadUnb 用"机器负荷差最大值"（物理上界）而非 makespan 上界做分母，使两目标落在真正可比的 [0,1] 量级。这是数值修正（属 solver 数值改动，需零回归重跑），值得单独立项。

第三，大实例求解质量偏弱。`tests/stage7_run.m` 的 BKS 表（MK01=40 … MK10=297）与内存记录的真实数据：MK01=40（达 BKS）、MK04=73（优于 BKS 81）、MK08=542（gap 3.6%）、但 MK02/03/06 等较大实例 gap 高达 +57%~+104%。对 TEVC 这类要求"标准基准 + 显著竞争力"的期刊，大实例系统性偏弱是必须解决的主诉，否则 SOTA 对比表格（aoo/ga/pso/alns/random）难以成立。建议优先确认 MK02-10 的 `.fjs` 是否齐备（`data/` 下 10 个 `.fjs` 已存在，但 `load_benchmark` 仅内置 MK01，其余靠 `find_fjs` 自动探测）——若实例齐备，应补齐 N=30 的标准长跑。

---

## 二、方案侧评价（Algorithm / Method）

方案侧由 `deepseek_chat.m`（API + 离线 mock + 缓存）、`parse_contract.m`、`offline_structured_modulate.m` / `online_llm_modulate.m`、`aoo_engine.m`（五策略：风/水/动物/滚动/弹射 + Lévy 扰动）、`llm_guided_local_search.m`、`critical_path.m` 构成。链路为：deepseek_chat → parse_contract（产出 diff_gain / levy_gain / explore_bias 三增益）→ 每代回灌 aoo_engine 的算子参数。

优点与成熟度：双引擎链路经多次审计确认通畅、无 NaN/Inf 泄漏（`nan_count` 守卫完善）；三增益均真实回灌 AOO（explore_bias 已接入风传播 `windPm`，diff_gain 同时调制水传播与动物传播，levy_gain 缩放 Lévy 跳跃）——五策略 × 三增益的耦合在代码层已闭环。离线降级（无 Key 自动本地启发式）使论文可复现、可离线跑；`env_state` / `llm_counts` 顶层字段使每个 JSON 自带"是否联网产物"证据，是对"LLM 贡献是否真实"这一核心审稿质疑的正面回应。

方案侧的主要风险：

第一，联网 LLM 增益的"真实性"在难实例上仍缺证据。`tevc_llm_gain.m` 已设计三臂消融（aoo / modulate / full）并加了环境态诚实探测（Key + 网络可达探针），但根因是当前运行环境网络不可达，full ≡ modulate，增益恒为 0（环境事实，非缺陷）。这意味着投稿主结果中的"LLM 提升"本质上仍是本地结构化调制代理。若论文把 LLM 作为核心 novelty，这是证据链条的关键缺口，需 `DEEPSEEK_API_KEY` + 网络复跑并在难实例（MK04/06/09）+ 动态/多目标场景量化真实增益。

第二，算子与增益的耦合是逐步补丁式，缺乏一处统一可验证声明。当前仅靠回归套件门禁间接保证，审稿人难以直接核验调制机制。建议补一张"五策略 × 三增益映射表"加单元测试断言（每个增益至少影响一个算子的参数），把隐式耦合显式化。

第三，`parse_contract.m` 解析了 `dynamic_strategy` / `priority` 字段但主链未消费（代码内有明确"未消费，防虚假双引擎声明"注释）——这是诚实做法，但需要确认论文正文不会误把这两个字段描述为已参与的搜索维度。

第四（轻微）：`aoo_engine.m` 第 300 行 `aoo.quality = result.quality;` 在函数体内引用了未定义的 `aoo` 局部变量。由于 MATLAB 对未声明变量做结构体动态赋值不会报错，该语句只会静默创建一个不被返回的本地 `aoo` 结构体，真正的 `result.quality` 已在第 293/295 行赋值并已通过输出参数返回（故三目标 HV/IGD 实际上能正常导出，stageB 实证也证实了这一点）。该行是无害的死代码，但易误导阅读者以为 `aoo.quality` 是回传通道，建议删除。

---

## 三、可视化设计评审

可视化侧已完成五件套：Plotly 甘特（`plotly_gantt.py`）、Plotly 收敛带（`plotly_convergence.py`）、动态回放（`replay_dynamic.py`）、Streamlit 仪表盘（`dashboard.py`）、数字孪生 3D（`digital_twin.py`）。ADDITIVE、只读 JSON，不触碰求解器数值，零回归纪律良好；dashboard 递归发现、INDEX 导航、契约版本告警（`<1.1` 提示归一化格式）均到位。`make_pareto_figure` 现在优先读 `pareto.mk/lb`（真实刻度）而非归一化值，并据 `energy_n` 显式色轴区分 2/3 目标——旧版"Pareto 横纵轴是 0~1 归一化、读不出真实 makespan"的问题已修复。

仍需指出两点契约层面的小问题：

其一，收敛曲线 y 轴语义依赖导出端是否带 `trace_makespan`。`plotly_convergence.py` 与 `dashboard.make_convergence_figure` 都优先读 `trace_makespan`（真实 makespan），缺失时回退 `trace_best`（归一化加权和）并明确标注 normalized——逻辑正确。但 `export_conv_json.m`（单 run 收敛序列，供 std 带聚合）同样优先 `trace_makespan`，旧版导出若无此字段则 fallback 到归一化 `trace_best`。由于 `EXPORT_CONV_JSON` 默认 false，批量 std 带仅在显式调用 `tests.stageC_conv_batch` 时产生，需确保该路径产出的是真实 makespan 序列而非归一化序列，否则聚合带仍会"虚低"。验证：`aoo_engine` 已写 `conv_mk`（真实），`llmaoo` 透传为 `trace_makespan`，故当前路径正确；仅需文档确认。

其二，`dashboard` 的 Replay 标签页与 `digital_twin.py` 的 replay 分支契约已对齐（均读 `frames:[{time,type,desc,schedule}]` 或 `kind=='dynamic_replay'`），`export_replay_json.m` 统一置 `kind='dynamic_replay'` 并带 `schedule` 数组与可选 `makespan`，两消费端对称，无旧版的 `bars/events` 误读问题。此项已收口，健康。

---

## 四、结果存储设计评审

结果以 JSON 契约存于 `results/` 下按场景分子目录（tevc_submission / stage5_benchmark / hot_dynamic / stageF_real / llm_gain_quant 等），含 `schedule`（array-of-arrays + `schedule_cols`）、`loadVec`、`trace_best/trace_mean/trace_makespan`、`pareto`、`quality` 等；`results/INDEX.md` 为导航索引。`export_result_json.m` 契约已升至 v1.2，关键改进：顶层 `mk_ub`、`cfg_hash`、`seed`、`env_state`、`llm_counts`；`pareto` 同时保留真实 `mk/lb` 与完整 `obj3`（供 NSGA-III 指标）+ 显式 `energy_n` 色轴；收敛同时存归一化 `trace_best` 与真实 `trace_makespan`。这些修复消除了旧版的"归一化值冒充真实值"误导，是契约层面的实质进步。

存储设计的具体问题（均为小修，非阻断）：

第一，字段语义易混且缺少量纲声明。导出 `loadVec=[35,39,...]` 是各机器负荷之和，而顶层 `loadUnb=7` 是 max−min 不均衡度——两者命名相近易混；`pareto.mk/lb` 是真实值，`pareto.obj3` 是归一化三向量——同一 `pareto` 内混存真实与归一化量。建议在 `results/README.md` 或 `INDEX.md` 用一张字段表明确每个字段的量纲（"sum load" vs "unbalance = max−min"，"real" vs "normalized"）。

第二，Pareto 契约 `obj3` 前三列的冗余。`obj3` 前两列 == `mk_n`/`ld_n`（即 `mk/mk_ub`、`lb/mk_ub`），而 `mk/lb` 已是真实值，前端可由 `mk/mk_ub` 派生前两列。保留完整 `obj3` 是为 NSGA-III 指标链（HV/IGD 计算需用归一化向量），属合理保留，但应在导出端注释清楚前两列可由 `mk/lb` 派生，避免前端/下游对 `obj3` 前两列做重复存储或误读。

第三，JSON 大小与可复现性。单结果约 127 KB 尚可；`result.cfg_hash`（关键超参 FNV-1a 哈希）与 `seed` 已写入，复现性良好。唯一建议：`export_result_json.m` 默认文件名用 `datestr(now,...)` 时间戳，实际 bat 调用已显式传路径（如 `logs/stageF_result.json`），无大问题；但 `pareto` 含 `OS`/`MS` 染色体 cell 数组（每个非支配解一份），当三目标 Pareto 点数较多时会显著膨胀体积，可考虑导出时仅存 `mk/lb/obj3` 与能量色轴，染色体按需另存，减小体积。

第四（已核对，健康）：`dashboard.make_overview_table` 读取 `stage5_benchmark.json` 的 `aoo_best`/`bks`/`gap_best_pct` 字段，与 `tests/stage7_run.m` 导出完全一致；`final_best` 统一为真实 makespan（C3 修正），`sota_worst` 单列最差成绩，列义清晰。该部分契约对齐良好。

---

## 结论

项目在工程成熟度、零回归纪律、双引擎链路完整性、存储契约诚实性上已经达到投稿级基础水准；问题侧场景覆盖广、解码稳健，可视化五件套与递归发现机制健康，存储 v1.2 已修复旧版最大误导。要真正冲击 TEVC，最关键的三个改进依次是：(1) 修正 loadUnb 归一化分母（用负荷差物理上界而非 makespan 上界），否则"双目标均衡"名不副实；(2) 在难实例（MK02-10）上补齐 N=30 标准长跑并确认 SOTA 竞争力，否则对比表格难以成立；(3) 在联网环境量化真实 LLM 增益，补齐 novelty 证据链。中等优先级：明确多目标立场（真 NSGA-III 主链 or 诚实定位为加权和自适应搜索）、删除 `aoo_engine.m` 第 300 行死代码、在 README 补一张存储字段量纲表。可视化与存储的其余设计只需上述契约小修即可消除全部误导风险。

## 限制

本评审基于静态代码逐行阅读与既有日志/导出 JSON 抽样，未实际运行完整 MK01-10 SOTA 长跑（约 30-60 分钟）；MATLAB `-batch` 在当前 PowerShell 环境下的引号冲突导致无法在此会话内跑 `tests.run_all` 回归验证，故对 `aoo_engine.m` 第 300 行的定性结论（无害死代码）依据代码路径与 stageB 既有实证推断，建议作者在下次回归时顺手删除该行。`load_data.m` 不读 `.fjs` 的限制仅影响 `llmaoo` 默认 static 路径；本项目标准基准实际经由 `load_benchmark.m` 的 `parse_fjs` 读取 `.fjs`，故该限制对基准实验不构成阻塞（旧内存笔记关于 `tevc_llm_gain` 传 `.fjs` 崩溃的判断在当前代码结构下已不成立）。

## References

1. [aoo_engine.m — AOO 五策略引擎（含 NSGA-III 主选与 Pareto 存档）](c:/Users/Joyce_SUN/Desktop/FJSP/aoo_engine.m)
2. [evaluate.m — 单染色体多目标适应度评估（归一化入口）](c:/Users/Joyce_SUN/Desktop/FJSP/evaluate.m)
3. [decode.m — semi-active 解码与 AGV/active 后处理](c:/Users/Joyce_SUN/Desktop/FJSP/decode.m)
4. [load_data.m — 实例加载与 mk_ub 上界计算](c:/Users/Joyce_SUN/Desktop/FJSP/load_data.m)
5. [benchmarks/load_benchmark.m — 标准 .fjs 解析与 BKS 注入](c:/Users/Joyce_SUN/Desktop/FJSP/benchmarks/load_benchmark.m)
6. [exports/export_result_json.m — 结果 JSON 契约 v1.2](c:/Users/Joyce_SUN/Desktop/FJSP/exports/export_result_json.m)
7. [exports/export_conv_json.m — 单 run 收敛序列（std 带聚合）](c:/Users/Joyce_SUN/Desktop/FJSP/exports/export_conv_json.m)
8. [viz/dashboard.py — Streamlit 仪表盘（Pareto/收敛/回放/对比）](c:/Users/Joyce_SUN/Desktop/FJSP/viz/dashboard.py)
9. [tests/stage7_run.m — 投稿级基准与 SOTA 实证](c:/Users/Joyce_SUN/Desktop/FJSP/tests/stage7_run.m)
10. [README.md — 项目说明与配置字段表](c:/Users/Joyce_SUN/Desktop/FJSP/README.md)
