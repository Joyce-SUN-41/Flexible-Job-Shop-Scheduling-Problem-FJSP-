# FJSP-LLMAOO 项目现状评审：问题侧 / 方案侧 / 可视化与结果存储

## Executive Summary

本项目是面向 IEEE TEVC 投稿的柔性作业车间调度（FJSP）求解器，核心设计为"LLM 契约解析 + AOO（自适应算子优化）五策略双引擎"。本次在 2026-08-14 历史评审基础上复检，确认工程成熟度、零回归纪律、双引擎链路完整性进一步稳固，回归套件已扩展到 18 个门禁（含阶段 A/B/C/D/F/G/H 与最火场景 gate）。值得肯定的是：**可视化与结果存储契约在 Stage9-viz 修复后已基本落地真实刻度**——当前代码导出的 `stageF_result.json` 中 Pareto 的 `mk=318/lb=247` 已是真实 makespan/负荷不均衡，历史报告中"Pareto 坐标不可解读 / mk_ub 未写入"两点在当前代码已解决。但仍有三类实质性问题需正视：一是方案侧主链仍是两目标加权和而非真正 Pareto 优化，且三目标存档的能量第三维严重退化（旧投稿主结果 `tevc_full_result.json` 中 energy 恒为 0.6645）；二是问题侧大实例（MK02/03/06）求解质量偏弱、联网 LLM 真实增益仍未量化；三是结果存储存在契约语义歧义（投稿主结果与最新代码导出格式不一致、`has_dynamic` 标志与动态主链脱节、Overview/卡片仍显示归一化 `final_best`）。

## 一、问题侧评价（Problem Formulation）

问题侧由 `load_data.m` / `benchmarks/load_benchmark.m` / `define_problem.m` / `attach_stage8.m` / `decode.m` / `evaluate.m` 构成，支持 static / green / transport / multi / dynamic / full 六种场景，并以两目标（makespan + 机器负荷不均衡）或三目标（加 energy）运行。

优点与成熟度体现在以下几点。第一，数据载入防御性极强：`load_data` 校验必需字段、两层 cell 结构、机器编号合法性、`mk_ub` 正有限性，所有断言在 fail-fast 处报错而非静默崩溃。`load_benchmark` 同时兼容 FJSPLib 标准 layout A（首 token=工序数）与 wrqccc layout B（首 token=op1 的 altCount）两种格式，并对 0-index 文件做 +1 平移、对越界 ID 做钳制，机器号归一化稳健，且不篡改声明的 `numMachines`。第二，归一化集中处理：`evaluate.m` 是唯一的归一化入口，以固定理论上界 `mk_ub`（各工序最快可选机器工时之和）归一化 makespan 与 loadUnb 到 [0,1]，消除了早期跨代量纲漂移与"makespan 量级淹没 loadUnb"的暗伤。第三，`decode.m` 的工序内序号推导已修复为 `kk = sum(OS(1:t)==j)`（与解码一致），正确处理了工件工序数不等实例（MK04/05/08/09/10），`active_postprocess` 可选地进一步压榨 makespan（默认关，零回归）。

问题侧仍存在的短板。第一，多目标建模不够"真"。虽然 `aoo_engine` 在 `AOO_THREE_OBJ=true` 时启用 NSGA-III 主选择（Das & Dennis p=12，91 参考点）并累积真实非支配前沿，但**默认 `AOO_THREE_OBJ=false`**，主链仍把 makespan 与 loadUnb 用 `w=[1,1]` 加和为单一标量（见 `obj_of`/`obj_eval`），并非真正的 Pareto 优化。换言之，NSGA-III 主选择只是开关选项，投稿主结果走的是加权和。若论文以"多目标 FJSP"为核心 novelty，审稿人会指出主链并非 NSGA-II/III 支配排序。第二，三目标的 energy 维度严重退化。根因在于主链的加权和中 energy 权重恒为 0（`evaluate` 中 `w3=0`），energy 不参与选择；NSGA-III 仅在显式开启时参与，但即便开启，从旧投稿主结果 `tevc_full_result.json` 可见 `obj3` 第三列恒为 ~0.6645、前两维 mk 仅取 0.264/0.285 两值、lb 恒 0.05——说明即便三目标分支，非支配前沿的 energy 被压成同一常数（机器权重 `machW` 全 1 导致 `energy=处理时间`，而前沿解对应的机器指派使 energy 归一化后收敛到同一值）。HV/IGD 指标在第三维退化的前提下意义有限，投稿时易被质疑。第三，大实例求解质量偏弱。既有真实数据：MK01=40（达 BKS）、MK04=73（优于 BKS）、MK08=542（gap 3.6%），但 MK02/03/06 等大实例 gap 高达 +57%~+104%，对 TEVC 要求的"标准基准 + 显著竞争力"是硬门槛，SOTA 对比表格难以成立。第四，AGV 运输建模过于简化：`attach_agv` 用 `abs(a-b)*0.5` 的曼哈顿式距离作为任意两机间运输时间，未考虑车间拓扑或 AGV 容量排队，作为"运输约束"证据偏弱。

## 二、方案侧评价（Algorithm / Method）

方案侧由 `deepseek_chat.m`（API + 离线 mock + 缓存）、`parse_contract.m`、`offline_structured_modulate.m` / `online_llm_modulate.m`、`aoo_engine.m`（五策略离散算子 + Lévy）、`llm_guided_local_search.m`、`critical_path.m`、`llm_hook.m` 组成。链路为：`deepseek_chat` → `parse_contract`（产出 `levy_gain`/`diff_gain`/`explore_bias` 三增益）→ `make_llm_state` → 每代回灌 `aoo_engine` 的算子参数。

优点与成熟度。第一，双引擎链路完整且经 2026-08-15 全链路审计确认无死锁、无 NaN/Inf 泄漏（`nan_count=0`），三增益均真实回灌 AOO（此前 `explore_bias` 死参数已修复，风传播 `windPm = max(0.15*c*explore_bias+0.02, AOO_MIN_EXPLORE)`；水传播此前仅 M3 受调，现已乘 `diff_gain`）。第二，离线降级设计（无 Key 自动本地启发式）使论文可复现、可离线跑，`cfg_hash` 与 `seed` 写入导出 JSON 支持可复现性。第三，`online_llm_modulate` 的诚实归因是对"LLM 贡献是否真实"这一审稿核心质疑的正面回应——在线时保留真实增益，离线/cached/fallback 回落到离线结构化调制，保证 `ablation('full')==('modulate')` 离线诚实。第四，回归套件极其扎实：`tests/run_all.m` 已扩展到 18 个门禁（checkcode 0 ERROR、decode_eval 自测、smoke、AOO vs Random 竞争力门禁 p 不显著劣化、stage8/9/A/B/C/D/F/G/H 各模块端到端、SOTA 证据链、定向鲁棒性），且刻意把重计算（N=30 完整实验）从自动套件中剥离以防超时，工程纪律优秀。

方案侧的主要风险。第一，LLM 增益的真实性在难实例上仍缺证据。阶段 D 已证 MK01 增益=0%，根因是运行环境无 DeepSeek 网络访问（走 mock 分支）。这意味着投稿主结果中的"LLM 提升"本质仍是本地启发式调制，联网 LLM 在难实例（MK04/06/09）上的真实增益未量化。若论文把 LLM 作为核心 novelty，这是证据链关键缺口。第二，五策略与三增益的耦合是逐步补丁式的，缺乏一处统一可验证声明（映射表 + 单元测试断言每个增益至少影响一个算子参数）。当前仅靠回归门禁间接保证，审稿人难以直接核验调制机制完整性。第三，门禁 [6] 仍按两目标 AOO vs Random 表述（p=0.5648 不显著劣化），未补三目标场景竞争力表述；一旦启用 NSGA-III 主选，该门禁需同步升级，否则"竞争力"证据与"多目标"主张不一致。第四，局部搜索与精英精炼的改进判据用字典序（`mk2<curMk-1e-9 || (abs==0 && unb2<curUnb-1e-9)`），在强约束下可能过早收敛，但属于可接受的经典局部搜索行为。

## 三、可视化设计评审（当前现状）

可视化侧已完成五件套：Plotly 甘特（`plotly_gantt.py`）、Plotly 收敛带（`plotly_convergence.py`）、动态回放（`replay_dynamic.py`）、Streamlit 仪表盘（`dashboard.py`，六标签页：Overview / Gantt / Convergence / Replay / Dynamic Compare / Pareto）、数字孪生 3D（`digital_twin.py`，自包含 Three.js HTML）。全部 ADDITIVE、只读 JSON、不触碰求解器数值，零回归纪律良好。

**相对历史报告的进展（已修复）**：历史报告第三节指出"Pareto 标签页坐标不可直接解读（mk≈0.26 归一化）"与"收敛曲线语义模糊（trace_best 归一化 0.3）"。经核对当前代码，这两点已实质性修复：`aoo_engine.m` 的 `build_pareto` 三目标分支现输出**真实** `mk/lb`（`mk_raw = mki` 来自 `decode`），`export_result_json.m` 导出真实 `mk/lb` 并写入 `mk_ub`/`cfg_hash`/`seed`；`dashboard.make_pareto_figure` 已改为读 `result["pareto"]["mk"|"lb"]`（真实值）作图，`make_convergence_figure` 优先读 `trace_makespan`（真实刻度），`plotly_convergence.py` 同样优先 `trace_makespan` 并在 y 轴标注"Makespan (real time)"。真实导出样例 `results/stageF_real/stageF_result.json` 验证：`mk=318, lb=247`（真实值）。因此"可视化刻度不可解读"在**当前代码**已不再是问题。

仍需注意的可视化问题。第一，旧投稿主结果 `results/tevc_submission/tevc_full_result.json`（generated 2026-08-14，早于 Stage9-viz 修复）仍是归一化导出（mk=0.264、lb=0.05、energy=0.6645），且与当前代码格式不一致。若该文件用于论文插图，读者看到的 Pareto/收敛仍是归一化刻度，需在投稿前用当前代码重新导出。**这是存储层遗留，不是代码 bug**。第二，`summary_cards` 与 Overview 表仍把 `final_best = tb[-1]` 显示为归一化加权和末值（`trace_best`），而卡片顶部的 Makespan 用真实值——同一页面出现"真实 makespan"与"归一化 final_best"两套语义，易让读者混淆。建议 Overview/卡片统一改用真实 `makespan`（已可用）或显式标注"final_best = normalized objective"。第三，`digital_twin.py` 的 replay 分支把机器轴 `y` 与作业轴 `z` 的处理中，`z` 实际恒为 0（`((o.job-1) % nJob) * 0.0`），多作业无法在 Z 方向分层，3D 视图的"作业泳道"退化成一平面叠加，区分度不足（仅颜色编码 job）。第四，dashboard 的收敛标签页靠文件名模式 `*_conv_*.json` 发现独立 run 文件，但当前导出端 `export_result_json` 并不产出 `*_conv_*.json`（仅产出单次 `results_<date>.json`），故多次独立 run 的 ±std 带在当前默认导出下为空——需配合 `experiment_runs`/`stageF_run` 的独立 run 导出才能显示，契约两端未对齐。

## 四、结果存储设计评审

结果以 JSON 契约存于 `results/` 下按场景分子目录（tevc_submission / stageF_real / hot_dynamic / hot_full / hot_multi / fullchain_demo），含 `problem`/`schedule`（array-of-arrays，列名 `schedule_cols`）/`loadVec`/`makespan`/`loadUnb`/`trace_*`/`pareto`/`quality` 等；`dashboard.discover_results` 递归匹配 `tevc_*/hot_*/stageF_*/_result.json/_replay.json` 可发现全量导出。结构清晰、可发现性强，序列化用 struct array 直出扁平数组（规避了 MATLAB `jsonencode` 列 cell 双重嵌套坑），Python 端兼容 array-of-arrays / list-of-dicts / column-dict 三种形态，健壮性好。

存储设计的具体问题。第一，**契约语义歧义：投稿主结果与最新代码不一致**。最新代码导出的 `stageF_result.json` 已用真实 `mk/lb` + `mk_ub`，但 `tevc_full_result.json` 仍用旧归一化格式且 `problem.has_dynamic=true` 与 `has_energy=true` 同时为真——但静态求解并不会真正走动态主链（`llmaoo` 仅在 `AOO_DEFAULT_SCENARIO != static` 时设 `cfg.AOO_DYNAMIC`，且 `attach_stage8` 不设 `has_dynamic`）。也就是说该 JSON 的 `has_dynamic` 标志是来自 `define_problem` 的 green/multi/full 路径被手工混入，与"是否真做动态重调度"脱节，元数据不可信。第二，**`has_dynamic`/`has_agv` 标志来源分裂**：`export_result_json` 从 `prob.has_dynamic` 读，但 `prob.has_dynamic` 由 `define_problem`（dynamic/full 模式）设置，`attach_stage8` 从不设置它，而 `llmaoo` 的 Stage A 仅设置 `cfg.AOO_DYNAMIC`（cfg 层），不回写到 `prob.has_dynamic`。三处标志（cfg.AOO_DYNAMIC / prob.AOO_DYNAMIC / prob.has_dynamic）语义重叠且不同步，前端/dashboard 若依赖 `prob.has_dynamic` 判断动态场景会误判。建议统一为单一权威标志（推荐 `prob.AOO_DYNAMIC`，由 `attach_stage8` 据 `cfg.AOO_DYNAMIC` 设置）。第三，**Pareto 存档维度冗余与不统一**：`pareto` 同时存 `mk/lb`（真实）、`mk_n/lb_n`（归一化前两维）、`Z`（=mk_n/lb_n 重复）、`obj3`（三列，前两列==mk_n/lb_n，第三列 energy）。`obj3` 前两列与 `mk_n/lb_n/Z` 信息完全重叠，约 563 点 × 冗余列增大体积且存在不一致风险；且两目标默认路径 `build_pareto` 已统一补 `obj3` 第三维为 NaN（这一点已修，前端色轴兜底正确），但导出端仍重复写 `Z` 与 `mk_n/lb_n`。建议导出端只保留 `mk/lb` + `obj3`，从前两列派生归一化值，删除 `Z`/`mk_n`/`lb_n` 冗余键。第四，`trace_best`/`trace_mean` 仍是归一化加权和（`aoo_engine` 中 `conv_best=sum(eliteObj)`），与 `trace_makespan`/`trace_loadUnb`（真实）并存双轨——前端已优先用真实轨，但 `trace_best` 仍作为 `summary_cards.final_best` 显示，如前所述语义不清。第五，可复现性元数据已写入（`cfg_hash`/`seed`/`scenario`/`mk_ub`），但 `cfg_hash` 使用的 FNV-1a 哈希实现（`llmaoo.m` 的 `cfg_hash`）在小字符串扰动下碰撞概率未量化，建议改用 MATLAB 内置 `string` 哈希或追加关键开关（如 `AOO_THREE_OBJ`/`OFFLINE_STRUCTURED_MODULATE`）到可读字符串而非仅 8 位十六进制，便于人工溯源。

## 结论

项目在工程成熟度、零回归纪律、双引擎链路完整性、回归套件覆盖度上已经达到投稿级基础水准，问题侧场景覆盖广、数据防御稳健，方案侧 LLM-AOO 耦合机制闭环且无暗伤。相对 2026-08-14 评审，可视化与存储契约的"真实刻度"问题已实质性修复（当前代码导出真实 mk/lb 并写 mk_ub，前端优先真实轨），这是关键进展。要真正冲击 TEVC，最关键的改进有四项：(1) 明确多目标立场——要么把默认主链升级为真实 NSGA-III 支配排序（而非加权和），要么在论文中诚实定位为"LLM 引导的加权和自适应搜索"，并解决三目标 energy 第三维退化（让 energy 在主链真正参与选择，而非仅存档投影）；(2) 在难实例上量化真实联网 LLM 增益，补齐 novelty 证据链；(3) 统一结果存储契约的标志位（`prob.AOO_DYNAMIC` 单一权威）并清理 `tevc_submission` 下的旧归一化投稿主结果，用当前代码重新导出，避免论文插图与正文语义脱节；(4) 去除 Pareto `obj3` 与 `Z/mk_n/lb_n` 的冗余列、统一 Overview/卡片的 `final_best` 为真实 makespan 或显式标注归一化。可视化其余设计（五件套、递归发现、INDEX 导航、struct-array 扁平序列化）是健康的，只需上述契约层面的小修即可消除误导。

## 限制

本评审基于静态代码阅读与对真实导出 JSON（`stageF_real/stageF_result.json`、`tevc_submission/tevc_full_result.json`）的抽样解析，对比了 2026-08-14 历史评审报告。未实际运行完整 MK01-10 SOTA 长跑（约 30-60 分钟），大实例 gap 数据来自既有 logs，建议以 N=30 重复实验确认。联网 LLM 增益因运行环境无 DeepSeek 网络访问未能实测，相关结论依据 `online_llm_modulate` 的离线 mock 路径与阶段 D 既有结论推断。energy 第三维退化结论依据旧投稿主结果 `tevc_full_result.json` 的 `obj3` 抽样（第三列恒 0.6645）及代码路径分析得出。
