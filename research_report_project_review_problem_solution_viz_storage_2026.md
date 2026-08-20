# FJSP-LLMAOO 项目评审报告：问题侧 / 方案侧 / 可视化与结果存储

## Executive Summary

本项目是一个面向 IEEE TEVC 投稿的柔性作业车间调度（FJSP）求解器，核心设计为"LLM 契约解析 + AOO（自适应算子优化）五策略双引擎"。经全面审查，问题侧与方案侧的**代码结构、双引擎链路、零回归纪律和 ADDITIVE 架构**都相当成熟，真实求解 MK01 达到 BKS=40，门禁检验 AOO 不显著劣于 Random（p=0.5648）。但存在三类需要正视的问题：一是方案侧目标建模为两目标加权和而非真正的多目标优化，削弱了 novelty 主张；二是结果存储契约在"归一化值 vs 真实值"之间存在语义混用，导致可视化（Pareto 散点、收敛曲线）显示的刻度不可直接解读；三是大实例（MK02/03/06）求解质量偏弱、联网 LLM 增益尚未在难实例上得到量化。以下分四部分详述。

## 一、问题侧评价（Problem Formulation）

问题侧由 `define_problem.m`、`evaluate.m`、`decode.m` 构成，支持 static / green / transport / multi / dynamic / full 六种场景，并能以两目标（makespan + 机器负荷不均衡）或三目标（加 energy）运行。优点：场景抽象清晰，归一化与反归一化在 `evaluate.m` 中集中处理，`decode.m` 的 active 解码与 `opOf` 工件内序号推导（2026-08-14 修复后）正确，`load_benchmark.m` 同时兼容标准 FJSPLib 与 wrqccc 两种 layout，机器号归一化稳健。

需要指出三个问题侧短板：

第一，多目标建模不够"真"。雖然代码同时维护两目标与三目标分支，并实现了 NSGA-III 质量指标（阶段 B：Das & Dennis p=12 + HV 蒙特卡洛 + IGD），但主求解仍然把 makespan 与 loadUnb 用固定权重 `w = [0.5,0.5]` 加和为单一标量（见 `aoo_engine.m` 的 `obj_of`），并非真正的 Pareto 优化。也就是说，论文若以"多目标 FJSP"为核心 novelty，投稿评审会指出其主链是加权和而非 NSGA-II / NSGA-III 支配排序。NSGA-III 的 `pareto` 存档与质量指标只是"附加证据"（默认 `AOO_THREE_OBJ=false`），并未进入选择算子。

第二，三目标分支的 energy 维度仅在"三目标激活 + 有能耗属性"时才评估（`build_pareto` 内 `hasEnergy`），而 tevc_full_result.json 显示 `problem.has_energy=True` 但导出里 `pareto.obj3` 第三维全部为 0.6645（几乎恒定）。这说明在默认场景下 energy 三目标并未真正参与搜索，前沿第三维退化，HV/IGD 指标意义有限——投稿时若报告 HV/IGD，需明确说明其是在加权和主导下的存档投影，否则易被质疑。

第三，大实例求解质量偏弱。真实数据：MK01=40（达 BKS）、MK04=73（优于 BKS）、MK08=542（gap 3.6%）；但 MK02/03/06 等较大实例 gap 高达 +57%~+104%。对 TEVC 这类要求"标准基准 + 显著竞争力"的期刊，大实例的系统性偏弱是必须解决的主诉，否则 SOTA 对比表格无法成立。

## 二、方案侧评价（Algorithm / Method）

方案侧由 `deepseek_chat.m`（API + 离线 mock + 缓存）、`parse_contract.m`、`offline_structured_modulate.m` / `online_llm_modulate.m`、`aoo_engine.m`（五策略：动物/水/风/滚动/弹出 + Lévy 扰动）、`llm_guided_local_search.m`、`critical_path.m` 组成。链路为：deepseek_chat → parse_contract（产出 diff_gain / levy_gain / explore_bias 三增益）→ make_llm_state → 每代回灌 aoo_engine 的算子参数。

优点与成熟度：双引擎链路经 2026-08-15 全链路审计确认通畅、无死锁、无 NaN/Inf 泄漏（nan_count=0），三增益均真实回灌 AOO（此前 explore_bias 死参数已修复，风传播 `windPm = max(0.15*c*llm_state.explore_bias + 0.02, ...)`）。离线降级设计（无 Key 自动本地启发式）使论文可复现、可离线跑。LLM 增益的诚实量化（`online_llm_modulate` 保真实增益）是对"LLM 贡献是否真实"这一审稿核心质疑的正面回应。

方案侧的主要风险：

第一，LLM 增益的"真实性"在难实例上尚缺证据。阶段 D 已证 MK01 增益=0%，根因是运行环境网络不可达（DeepSeek 实际走 mock 分支）。这意味着投稿主结果中的"LLM 提升"本质上仍是本地启发式调制，联网 LLM 在难实例（MK04/06/09）上的真实增益未量化。若论文把 LLM 作为核心 novelty，这是证据链条的关键缺口。

第二，五策略中"水传播"仅在近期修复后才乘 `diff_gain`（此前仅动物传播 M3 受调制），"风"刚刚接上 explore_bias。这说明算子与 LLM 增益的耦合是逐步补丁式的，理论上的"五策略 × 三增益"完整映射缺乏一处统一的可验证声明（如一张映射表 + 单元测试断言每个增益至少影响一个算子的参数）。当前仅靠回归套件门禁间接保证，审稿人难以直接核验调制机制。

第三，门禁 [6] 仍按两目标 AOO vs Random 表述（p=0.5648，不显著劣化），未补三目标场景竞争力表述。一旦启用 NSGA-III 主选，该门禁需同步升级，否则"竞争力"证据与"多目标"主张不一致。

## 三、可视化设计评审

可视化侧已完成五件套：Plotly 甘特（`plotly_gantt.py`）、Plotly 收敛带（`plotly_convergence.py`）、动态回放（`replay_dynamic.py`）、Streamlit 仪表盘（`dashboard.py`，三标签页：Overview / Gantt / Convergence / Replay / Pareto）、数字孪生 3D（`digital_twin.py`，自包含 Three.js HTML）。ADDITIVE、只读 JSON，不触碰求解器数值，零回归纪律良好。dashboard 的契约对齐（误读 `result.meta`→读 `problem`+顶层标量、replay 误读 `bars/events`→读 `schedule`+type/desc/time、schedule 归一化与 `finish` 字段修复）均已收口，真实数据闭环可跑（HTTP 200 探活通过）。

但可视化存在两个因上游契约引起的解读问题：

其一，Pareto 标签页坐标不可直接解读。导出 `result.pareto.mk` / `result.pareto.lb` 存的是**归一化值**（抽样 tevc_full_result：mk≈0.26、lb≈0.05），而真实 makespan=38、loadUnb=7。dashboard 的 `make_pareto_figure` 直接把 `p["mk"]`/`p["lb"]` 当坐标轴（第 351-354 行），因此图表横纵轴是归一化 0~1 刻度，读者无法读出真实 makespan/负荷；经 `evaluate.m` 反归一化所需的 `mk_ub`（BKS 上界）未被写入 JSON，前端无法还原。建议导出时**同时保留原始 mk/lb 与归一化值**（或在 `problem` 元数据中写入 `mk_ub`），并在坐标轴标注"normalized"。

其二，收敛曲线语义模糊。导出 `trace_best` 是归一化加权和（抽样末值 0.3214），dashboard 与 plotly 均标注 "Best objective / Best weighted objective"。读者看到 y 轴 0.3 左右，无法对应真实 makespan=38。建议导出**额外保留真实 makespan 的收敛序列**（如 `trace_makespan`），或在曲线旁以注释给出最终真实 makespan/loadUnb，避免"虚低"误导。

此外，`digital_twin.py` 支持 replay 分支（读 `kind=='dynamic_replay'`、`frames:[{time,type,desc,schedule}]`），但 `export_replay_json.m` 的产出是否每次都带 `kind` 字段需确认（dashboard 的 replay 解析依赖 `frames` 键，digital_twin 依赖 `kind` 或 `frames`）。两消费端契约不完全对称，建议在导出端统一置 `kind`。

## 四、结果存储设计评审

结果以 JSON 契约存于 `results/` 下按场景分子目录（tevc_submission / stage5_benchmark / hot_dynamic / stageF_real / llm_gain_quant 等），含 `schedule`（array-of-arrays，列名 `schedule_cols`）、`loadVec`、`trace_best/trace_mean`、`pareto`、`quality` 等；`results/INDEX.md` 为导航索引，各核心子目录有 README。结构清晰、可发现性强，dashboard 的 `discover_results` 递归扩展匹配 `tevc_*/hot_*/stageF_*/_result.json/_replay.json` 可发现 60 结果 + 10 回放。

存储设计的具体问题：

第一，归一化值污染原始语义（同第三节）。`pareto.mk/lb` 与 `trace_best` 都是归一化量，`schedule` 虽是真实的 `[job,op,machine,start,finish,duration]`，但 `loadVec=[35,39,39,33,32,37]` 是各机器负荷之和，而顶层 `loadUnb=7` 是 max−min 不均衡度——两者命名相近易混。建议在 README/INDEX 用一张字段表明确每个字段的量纲（"sum load" vs "unbalance = max−min"），并区分归一化与原始值。

第二，Pareto 存档的 `obj3` 仅三目标分支存在。抽样中 tevc_full_result（AOO_THREE_OBJ 激活）有 `obj3`，但两目标默认路径 `build_pareto` 不产出 `obj3`。dashboard 的 Pareto 标签页对 `obj3` 缺失有 `obj` 兜底（第 363 行），但兜底时能量色轴退化为全零。这意味着大量默认两目标结果在 Pareto 标签页会缺失能量维度——若论文只渲染三目标结果的 Pareto，会显得覆盖不全。建议统一契约：无论几目标，`pareto` 都带 `obj3`（无能耗时第三维置 NaN 并显式标注），保证前端渲染一致。

第三，JSON 大小与冗余。tevc_full_result.json 为 127 KB，单个结果尚可；但 `pareto.obj3` 存 563 点全三维（约 563×3），与 `pareto.mk/lb/obj` 信息重叠（obj3 前两列 == mk/lb）。存在重复存储，可在导出端只保留 `obj3` 并从前两列派生 mk/lb，减小体积并消除不一致风险。

第四，时间戳与可复现性。`export_result_json.m` 默认文件名用 `datestr(now,...)`，而实际 bat 调用已显式传路径（如 `logs/stageF_result.json`），无大问题；但 `result` 未写入随机种子 / 配置哈希，难以把某个 JSON 精确回溯到某次 `llmaoo_config` 设置。投稿级复现建议：在 JSON 顶层写入 `cfg_hash`（关键超参的简短哈希）与 `seed`。

## 结论

项目在工程成熟度、零回归纪律、双引擎链路完整性上已经达到投稿级的基础水准，问题侧场景覆盖广、方案侧 LLM-AOO 耦合机制已闭环且无暗伤。要真正冲击 TEVC，最关键的三个改进是：(1) 明确多目标立场——要么把主链升级为真实的 NSGA-III 支配排序（而非加权和），要么在论文中诚实定位为"LLM 引导的加权和自适应搜索"；(2) 在难实例上量化真实联网 LLM 增益，补齐 novelty 证据链；(3) 修复结果存储契约中的"归一化值 vs 真实值"混用，让可视化（尤其是 Pareto 与收敛曲线）的刻度可被读者直接解读，并在 Pareto 契约中统一 `obj3` 维度。可视化与存储的其余设计（五件套、递归发现、INDEX 导航）是健康的，只需上述契约层面的小修即可消除误导性。

## 限制

本评审基于静态代码阅读与对 `results/tevc_submission/tevc_full_result.json` 的抽样解析，未实际运行完整 MK01-10 SOTA 长跑（约 30-60 分钟）。联网 LLM 增益因运行环境无 DeepSeek 网络访问，未能实测，相关结论依据 `online_llm_modulate` 的离线 mock 路径与阶段 D 既有结论推断。大实例 gap 数据来自既有 logs，建议以 N=30 重复实验确认。
