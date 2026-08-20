# FJSP-LLMAOO 项目评审报告（当前状态，2026-08-18）

## Executive Summary

本次评审基于静态代码阅读与对 `results/tevc_submission/tevc_full_result.json`、`tevc_multi_result.json` 的真实抽样。结论是：项目在 2026-08-17 之后经历了一轮实质性收口，历史评审报告（`research_report_project_review_problem_solution_viz_storage_2026.md`）中的两条核心指控——"多目标为伪三目标"、"可视化 Pareto/收敛归一化不可读"——**均已修复**。当前代码已是 NSGA-III 真实三目标主选、`contract_version=1.1` 真实刻度契约、仪表盘对旧归一化契约显式告警。项目在工程成熟度与投稿基础水准上已达 TEVC 投稿门槛。仍存三类需正视的问题：大实例系统性偏弱（信誉主诉）、联网 LLM 真实增益未量化（证据链缺口）、以及结果存储中 `obj3` 维度约定冗余且语义脆弱（设计层面的隐患）。以下分四部分详述，并明确指出与旧报告的分歧。

## 一、问题侧评价（Problem Formulation）

问题侧由 `define_problem.m`、`evaluate.m`、`decode.m` 构成，支持 static / green / transport / multi / dynamic / full 六种场景，可两目标或三目标运行。场景抽象清晰：`define_problem` 与 `attach_stage8` 统一了 `AOO_THREE_OBJ / AOO_DYNAMIC / AOO_AGV` 单一权威标志位（消除历史三处分裂），`evaluate.m` 集中处理唯一归一化入口（固定理论上界 `mk_ub` / `e_ub`），`decode.m` 的 `opOf` 工件内序号推导已正确。

需要指出四个问题侧特征：

第一，多目标建模立场已澄清但需论文诚实定位。当前代码在 `AOO_THREE_OBJ=true` 时，由 `aoo_engine` 用 `nsga3_select` 真实替主链选择 N 个个体（L130-159），`evaluate` 第五输出 `[mk_n, ld_n, en_n]` 三目标向量，HV/IGD 由门禁 [10] 端到端验证。这确实是真实三目标，而非旧版"加权和伪多目标"。但默认 `false` 时主链仍是两目标加权和（权重 `W_MAKESPAN/W_LOAD`），且三目标主选下两目标加权和 `Z` 仍被同步计算供下游兼容。论文必须明确：默认路径是"LLM 引导的加权和自适应搜索"，投稿多目标路径是 NSGA-III 主选——二者是开关互斥的两种配置，不能混述为单一方法。

第二，三目标 energy 维度现在真实分化。抽样 `tevc_multi_result.json` 的 `obj3` 第三列 = [0.657, 0.681, ...]（每个非支配解不同），不再是旧版恒 0.6645 的塌缩。根因修复在 `evaluate.m` 的 `get_eub`：优先固定理论上界 `prob.e_ub`（attach_energy 构造），废弃旧版 `1.5*energy+1` 自适应渐近线。这是一次真实且有效的修复。

第三，大实例求解质量偏弱仍是信誉主诉。既有数据（阶段三.1）：MK01=40（达 BKS）、MK04=73（优于 BKS）、MK08=542（gap 3.6%）、MK03 达 BKS；但 MK02(+26.9%)/MK06(+65.5%)/MK09(+7.7%) 相对 BKS gap 较大。已做安全探索（`stage7_strong_x3.m` 仅调 `LS_KMAX/AOO_REFINE_EVERY` 运行时参数），结论是不可靠（激进版 MK02 改善但保守版全面退化）。对 TEVC 这类要求"标准基准 + 显著竞争力"的期刊，大实例系统性偏弱是必须诚实讨论或在方法中补偿的主诉，否则 SOTA 对比表格无法全面成立。

第四，归一化量纲的工程设定合理但有隐含代价。`evaluate` 用 `mk_ub`（各工序最快可选机器工时之和）归一化 makespan 与 loadUnb 到 [0,1]。这解决了旧版 makespan(~200) 量级淹没 loadUnb(~30) 导致"双目标均衡"名不副实的问题。但 `mk_ub` 是乐观下界而非可达上界，归一化后两目标数值偏"小"，仅用于搜索内部比较，真实刻度由导出端 `mk/lb` 单独保留——设计上已分离，无泄漏风险。

## 二、方案侧评价（Algorithm / Method）

方案侧由 `deepseek_chat.m`（API + 离线 mock + 缓存）、`parse_contract.m`、`offline_structured_modulate.m` / `online_llm_modulate.m`、`aoo_engine.m`（五策略：风/水/动物/滚动/弹射 + Lévy 扰动）、`llm_guided_local_search.m`、`critical_path.m` 组成。双引擎链路为：deepseek_chat → parse_contract（产出 diff_gain / levy_gain / explore_bias 三增益）→ 每代回灌 aoo_engine 算子参数。

方案侧成熟度较高：

第一，五策略与三增益的耦合已完整闭合。历史遗留的"explore_bias 死参数"已修复（风传播 `windPm = max(0.15*c*llm_state.explore_bias + 0.02, ...)`），"diff_gain 仅调水传播"也已补（aoo_params 中 `m = m * llm.diff_gain`）。三增益现均真实消费：levy_gain 调 Lévy 振幅、diff_gain 调水/动物强度、explore_bias 调风变异幅度。离线降级（无 Key 自动本地启发式）使论文可复现。

第二，精英关键路径局部搜索（`refine_elite`）与停滞重启（`elite_guided_restart`）是稳健的 FJSP 经典增强，频率受 `AOO_REFINE_EVERY` / `AOO_RESTART_PATIENCE` 控制，且 `opOf` 改用 `kk = sum(OS(1:t)==j)` 与 decode 一致，避免了历史越界崩溃（曾致 MK04/05/08/09/10 崩溃）。

第三，NSGA-III 主选实现正确。Das-Dennis 参考点生成（`das_dennis`，p=12 → 91 参考点）、非支配排序（`non_dominated_sort`）、参考点小生境选择（`nsga3_select`）三段齐备；三目标分支逐代累积真实非支配前沿 `pf3` 并去重（`unique(round(pf3c,6),'rows','stable')`），避免前端计数虚高。门禁 [9]（energy 分化 guard）+ [10]（HV/IGD 有限非负自检）端到端覆盖该路径。

方案侧仍存两个风险：

第一，联网 LLM 增益证据链缺口。阶段三.2 已诚实固化：当前环境离线，`tevc_llm_gain.json` 是 `full≡modulate` 的诚实产物（增益=0 是环境事实，非缺陷），配套 `env_manifest.json` 声明边界——论文不可宣称"在线 LLM 带来量化增益"。但投稿若以"LLM 引导"为 novelty 核心，缺少难实例上真实联网增益的量化对比是实质性缺口，须注入 `DEEPSEEK_API_KEY` 并确认 `api.deepseek.com` 可达后重跑 `tests.tevc_llm_gain`（5 场景 × 3 臂 × N=30 × MAXGEN=130）方能补证。

第二，门禁 [6]（AOO vs Random 竞争力）仍按两目标表述（p=0.5648 不显著劣化），未补三目标场景竞争力表述。一旦投稿走 NSGA-III 主选路径，该门禁需同步升级，否则"竞争力证据"与"多目标主张"口径不一致。

## 三、可视化设计评审

可视化侧五件套：Plotly 甘特（`plotly_gantt.py`）、Plotly 收敛带（`plotly_convergence.py`）、动态回放（`replay_dynamic.py`）、Streamlit 仪表盘（`dashboard.py`，六标签页）、数字孪生 3D（`digital_twin.py`，自包含 Three.js HTML）。纯读 JSON、ADDITIVE、不触碰求解器数值，零回归纪律良好。

历史报告指出的两个核心可视化问题**均已修复**：

其一，Pareto 坐标现在可直接解读。导出 `pareto.mk/lb` 已是真实 makespan/loadUnb（抽样 tevc_full_result：mk=[36,38,39]、lb=[14,16,7]），dashboard `make_pareto_figure` 直接读 `p["mk"]/p["lb"]` 作坐标轴；`mk_ub` 也已写入 JSON 供反归一化。不再是旧版 0.x 归一化刻度。

其二，收敛曲线语义已明确。导出 `trace_makespan`（真实逐代 makespan，抽样末段 [44,44,38]）与 `trace_loadUnb`；dashboard 与 plotly 均优先读 `trace_makespan`，标题标注 "Makespan (real time)"，仅在缺失真实序列时回退 `trace_best` 并标注 "normalized"。dashboard 还对 `contract_version < 1.1` 的旧 JSON 显式告警 "legacy/normalized format (makespan not real-scale)"，防止旧归一化数据混入误读。

此外，数字孪生 `digital_twin.py` 兼容 `kind=='dynamic_replay'` 与 `frames` 两种入口（`export_replay_json` 已统一置 `kind='dynamic_replay'`），两消费端契约对称；dashboard 的 replay/compare 标签页解析也据 `frames` 键稳健工作。

可视化仍有一个设计层面的隐患（见第四节与 storage 关联）。

## 四、结果存储设计评审

结果以 JSON 契约存于 `results/` 下按场景分子目录（tevc_submission / stageF_real / hot_dynamic / hot_multi / hot_full / stage9_export / llm_gain_quant 等），含 `schedule`（array-of-arrays + `schedule_cols`）、`loadVec`、`trace_best/trace_mean/trace_makespan/trace_loadUnb`、`pareto{mk,lb,obj3}`、`quality{HV,IGD,nPF}`，并写入 `cfg_hash`/`seed`/`scenario`/`mk_ub` 提升可复现性。结构清晰、契约稳定，dashboard 递归发现可覆盖 69 个导出文件。

存储设计的具体评价：

第一，契约版本治理是亮点。`contract_version='1.1'` 显式区分真实刻度契约与旧归一化契约，前端据版本告警——这是一次成熟的契约演进设计，避免了历史"归一化值污染原始语义"问题。

第二，字段量纲文档已完备。README "导出 JSON 契约" 段明确列出 `loadVec`（各机负荷和）vs `loadUnb`（max−min 不均衡），并区分归一化（obj3 前两列）与真实（mk/lb）。命名相近的歧义已在文档层消解。

第三（核心隐患），`obj3` 维度冗余且语义脆弱。导出契约中 `pareto` 同时保留 `mk/lb`（真实刻度）与 `obj3`（三列 [mk_n, ld_n, en_n]，前两列为归一化、第三列为 energy）。问题有三：(a) `obj3` 前两列与 `mk/lb` 信息重复（前者归一化、后者真实），且前端 Pareto 色轴只取 `obj3[:,2]`（energy），前两列实际未被 Pareto 图消费——存在冗余存储与"同一概念两套表达"的维护风险；(b) 两目标分支 `obj3 = [mk_n, ld_n, NaN]`，第三列恒 NaN，前端退化为单色——维度存在但语义非真，易让审阅者误以为三目标结果；(c) `obj3` 第三列的归一化 energy 与 `pareto.energy`（若存在）又可能双份。建议：要么把 Pareto 契约精简为 `{mk, lb, energy_n}`（真实 mk/lb + 归一化 energy，去掉 obj3 前两列冗余），要么在文档显式声明 `obj3` 是"NSGA-III 输入向量（含归一化前两维）"与 `mk/lb` 是"展示坐标"的分工，避免后续维护者混淆。当前功能正确，但语义边界含糊是真实的负债。

第四，JSON 体积可接受。tevc_full_result.json = 11 KB、hot_multi_result.json = 84 KB（多实例），单文件体量合理，未发现显著冗余膨胀。

第五，可复现性已较充分。`cfg_hash`（14 字段含 `W_ENERGY`/`ENERGY_UB`/`AOO_THREE_OBJ`）、`seed`、`scenario`、`mk_ub` 均已写入，可将 JSON 精确回溯到某次 `llmaoo_config` 设置——较历史状态显著改善。唯一缺口：`EXPORT_CONV_JSON` 默认 false，故 std 带默认不可用（这是零回归安全默认，非缺陷，已文档说明）。

## 结论

项目在工程成熟度、零回归纪律、双引擎链路完整性、契约版本治理上已达到投稿级水准；历史评审报告中的两条核心指控（伪三目标、可视化不可读）已被代码结构演进与真实导出抽样证伪。要真正冲击 TEVC，最关键的三个改进是：(1) 在论文中诚实区分"默认两目标加权和主链"与"投稿 NSGA-III 三目标主选"两种互斥配置，避免方法学表述混叠；(2) 在难实例上量化真实联网 LLM 增益（注入 Key 复跑 tevc_llm_gain），补齐 novelty 证据链，或诚实定位为"离线结构化调制"；(3) 收口 `pareto` 契约的 `obj3` 维度语义（消除 `mk/lb` 与 `obj3` 前两列的冗余双表达，明确 energy 色轴来源），并把大实例 MK02/06/09 偏弱作为 Limitations 诚实讨论。可视化与存储的其余设计（五件套、递归发现、INDEX 导航、contract_version 治理）是健康的。

## 限制

本评审基于静态代码阅读与对 `results/tevc_submission` 两份导出 JSON 的抽样解析，未实际运行完整 MK01-10 SOTA 长跑（约 30-60 分钟），亦未实际执行联网 LLM 增益复跑。大实例 gap 数据来自既有 `logs/stage7_benchmark.json` 与 README 阶段表，建议以 N=30 重复实验最终确认。联网 LLM 增益因运行环境无 DeepSeek 网络访问，结论依据离线诚实声明（`env_manifest.json`）推断。

## 与历史评审报告的分歧说明

2026-08-17 的 `research_report_project_review_problem_solution_viz_storage_2026.md` 作出两项核心指控：(1) "主求解仍把两目标加权和，NSGA-III 仅附加、伪多目标"；(2) "Pareto 坐标归一化不可读、收敛曲线虚低"。经本次代码与真实导出抽样核查，两项指控均已不成立——代码已升级 NSGA-III 真实三目标主选（`aoo_engine` L130-159 + `evaluate` 三目标分支 + 门禁 [9]/[10]），导出契约已落地 `contract_version=1.1` 真实刻度（`pareto.mk/lb` 真实、`trace_makespan` 真实、前端对 <1.1 告警）。旧报告应视为"修复前快照"，本次报告为当前状态评审。旧报告其余有效结论（大实例偏弱、联网增益缺口、obj3 冗余）已并入本报告并据新证据更新。

## References

1. [aoo_engine.m — NSGA-III 主选与五策略实现](c:\Users\Joyce_SUN\Desktop\FJSP\aoo_engine.m)
2. [evaluate.m — 唯一归一化评估入口与三目标分支](c:\Users\Joyce_SUN\Desktop\FJSP\evaluate.m)
3. [exports/export_result_json.m — v1.1 真实刻度契约](c:\Users\Joyce_SUN\Desktop\FJSP\exports/export_result_json.m)
4. [viz/dashboard.py — Pareto/收敛真实刻度消费与 contract_version 告警](c:\Users\Joyce_SUN\Desktop\FJSP\viz\dashboard.py)
5. [README.md — 项目状态与契约文档](c:\Users\Joyce_SUN\Desktop\FJSP\README.md)
6. [results/tevc_submission/tevc_full_result.json — 真实刻度导出抽样](c:\Users\Joyce_SUN\Desktop\FJSP\results/tevc_submission/tevc_full_result.json)
7. [results/tevc_submission/tevc_multi_result.json — 三目标 energy 真实分化抽样](c:\Users\Joyce_SUN\Desktop\FJSP\results/tevc_submission/tevc_multi_result.json)
