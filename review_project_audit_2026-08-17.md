# 项目整体审查报告（问题侧 / 方案侧 / 可视化 / 结果存储）

日期：2026-08-17
对象：FJSP LLMAOO 求解器（MATLAB 主链 + Python/Plotly 可视化）
目标期刊上下文：IEEE TEVC（要求 novelty / 标准基准 / 统计显著性 / 多目标 rigor）

## 一、问题侧评价（求解的是什么、做得对不对）

问题建模本身是标准、正确的 FJSP 设定：OS+MS 染色体、半主动解码（`decode.m`）、两目标（makespan + 机器负荷不均衡），并叠加了 energy / AGV / dynamic 三类扩展场景。解码层对机器索引做钳制、对 OS 做工序数守恒修复（`fix_os_counts`），稳定性好；`evaluate.m` 用固定理论界 `prob.mk_ub` 做归一化，解决了跨代量纲漂移，这是一处扎实的改进。

但问题侧有一个建模层面的硬伤，直接影响投稿定位：

1. 三目标"伪多目标"问题仍未根治。主链 `evaluate.m` 第 44 行 `w3 = 0`，即 energy 权重恒为 0。尽管三目标模式会计算并导出 `obj3 = [mk_n, ld_n, en_n]`、NSGA-III 分支（`aoo_engine` L130-154）也真实做了非支配排序，但**主选择开关 `AOO_THREE_OBJ` 默认 false**，且即便开启，主链加权合成里 energy 仍不进入 Z。这意味着：默认静态求解是一条单/双目标加权和路径，NSGA-III 只是"附加分析"。对 TEVC 而言，要么诚实定位为"LLM 引导的加权和自适应搜索，NSGA-III 作附加指标"，要么把 `w3` 真正接入（需新增 `cfg.W_ENERGY` 且默认非零），否则"三目标"表述在评审眼里是名不副实的。

2. 大/难实例偏弱。据阶段三.1 证据链（`logs/stage7_benchmark.json`）：MK01/03/04/05/07/08/10 达/超 BKS，但 MK02(+26.9%)、MK06(+65.5%)、MK09(+7.7%) 明显偏弱。对以基准对比为核心的 TEVC 投稿，这 3 个实例是审稿人会重点看的"弱点"，需要在正文里做诚实讨论或补强（如加强局部搜索、重启机制、增加种群/代数）。

3. 动态场景主链未真正启用。`AOO_DYNAMIC=true` 仅触发 `dynamic_replay.m` 的离线路演导出（Stage8 注释也写明"reactive main loop belongs to aoo_engine Stage8, kept separate"），主搜索循环本身没有事件驱动的再调度内循环。换言之动态能力目前停留在"演示/导出"层面，而非求解主链的真实能力——投稿时不能把 dynamic 描绘成主引擎特性。

## 二、方案侧评价（双引擎架构、算法设计）

方案设计（LLM 知识中枢 × AOO 五策略群体智能）在工程上是有想法、且工程纪律很好的：严格的"零回归边界"——所有新能力默认关，靠 `cfg` 开关激活；AOO 全部算子保留并仅接受 LLM 增益系数调制（不逐解计算）；`llm_hook` 抽成独立函数让主链与消融实验共享同一调制逻辑。这些 ADDITIVE 工程原则是项目最大的优点。

方案侧的具体问题：

1. LLM 增益链路在离线态本质是恒等变换。默认 `LLM_ENABLE=false`、无 Key 时所有 `levy_gain/diff_gain/explore_bias` 回退到契约解析的默认值（通常 1.0），即 `aoo_params` 里 `m = m * llm.diff_gain` 等于乘 1。离线 `full ≡ modulate`（已在 memory 中明确）。这意味着**双引擎协同的贡献在默认/离线运行下没有量化证据**，而联网增益实验（`tevc_llm_gain.m`）因缺 `DEEPSEEK_API_KEY` + 网络不可达，当前 `full` 仍 ≡ `modulate`，量化增益为 0。这是投稿最关键的"贡献是否被认可"风险点。

2. 算子有效性的理论支撑弱。AOO 五策略（风/水/动物/滚动/弹射）是将连续种子传播机制"映射"到离散 FJSP 的邻域算子，命名有创意但缺乏与 GA/ALNS/PSO 等经典 FJSP 算子的系统性对比证明"为何 AOO 更好"。阶段三.1 已给出 AOO 显著优于 GA/PSO/ALNS/Random 的 Wilcoxon 证据（p<0.001），这是好的，但 novelty 论证仍偏"工程组合"而非"算法原理创新"。

3. 局部开发依赖单一关键路径精炼。`refine_elite` 每 5 代对精英做一次关键机器邻域穷举，对中小实例够用，但对 MK02/06/09 偏弱可能说明精炼强度或触发频率不足。

## 三、可视化设计审查

可视化三件套（Plotly Gantt / 收敛 / Pareto）+ Streamlit 仪表盘 + Three.js 数字孪生，整体是现代化、可交互、ADDITIVE 的，且已修复多项旧 bug（真实刻度、Z 轴分层笔误、replay 分支契约）。具体评估：

优点：
- 收敛曲线优先读 `trace_makespan`（真实 makespan）而非归一化 `trace_best`，刻度可解读，这是关键修复。
- Pareto 图用真实 mk/lb 作坐标轴、energy 作色轴，契约清晰。
- digital_twin 已修正 `* 0.0` Z 轴笔误，按 job 在 Z 方向真实分层。

仍存在的问题：
1. 数字孪生的"扫掠平面"动画用 `t = (t + dt*makespan*0.12) % (makespan+20)`，时间速率与真实调度无关，仅为观感，可接受；但 boxes 仅按 job 着色、Z 按 `((job-1)%nJob)` 分层——当 nJob 较大时 Z 分层会循环重叠（多 job 共享同一 Z 带），可读性随作业数下降，建议改用 `job-1` 连续分层或按机器+作业双编码。

2. 概览表（`make_overview_table`）把 `benchmark` 行的 `final_best` 填成 `r.get("bks")`（理论最优），而 `mks` 填 `r.get("aoo")`——同一行里"mks"列是求得值、"final_best"列是 BKS，两个语义混在一张表里且无列名区分说明，易误读（读者可能以为 final_best 也是求得值）。建议 final_best 改名或明确标为 BKS。

3. 收敛 ±std 带默认为空。前端 `make_convergence_figure` 依赖 `*_conv_*.json` 独立 run 文件，但 `export_result_json` 默认不产出这类文件（仅主结果 JSON）。默认导出下 std 带永远不显示，收敛图只有单条 primary 线——对"统计显著性"展示不利。投稿需要的多 run 方差证据必须靠额外的 stage7 长跑脚本，建议把 std 带的产出也纳入默认导出路径或文档明确说明。

4. dashboard 的 `_RESULT_PATTERNS` 用 `tevc_*.json` 等宽匹配，且 `discover_results` 递归扫描 `logs/figures/results`，若目录里存在旧格式（归一化）JSON（如 `results/tevc_submission/tevc_full_result.json` 仍是 mk=0.264 旧格式），会被一并发现并渲染，前端会混显新/旧尺度数据。建议对旧归一化 JSON 做兼容标注或迁移。

## 四、结果存储设计审查

存储契约（MATLAB struct → JSON，Python 只读消费）设计总体合理、字段命名 ASCII、阶梯式修复冗余键。具体问题：

1. 旧投稿 JSON 未重导出。`results/tevc_submission/tevc_full_result.json`（gen 2026-08-14）仍是归一化旧格式（mk=0.264, lb=0.05, energy 恒 0.6645），且 `problem.has_dynamic=true` 与 `has_energy=true` 同时为真但静态求解未走动态主链——标志位语义脱节。投稿前必须用当前代码重导出，否则 reviewer 拿到的是不可解读的旧数据。

2. 标志位三处分裂虽已部分收敛，但仍有语义交叉。`cfg.AOO_DYNAMIC` / `prob.AOO_DYNAMIC` / `prob.has_dynamic` 三者在 `attach_stage8` 已统一为 `prob.AOO_DYNAMIC = cfg.AOO_DYNAMIC; prob.has_dynamic = cfg.AOO_DYNAMIC`（L64-67），这是改进；但 `define_problem` 里 `has_dynamic` 由 mode 设置，而 `attach_stage8` 用 `cfg.AOO_DYNAMIC` 覆盖——两条路径入口不同，直接调 `define_problem` 不走 `attach_stage8` 时 `prob.AOO_DYNAMIC` 不存在。当前主链 `llmaoo` 会调 `attach_stage8` 兜底，故实际无碍，但作为契约不够干净。

3. `cfg_hash` 已追加 `AOO_THREE_OBJ`/`ENERGY_UB` 等，但 `W_ENERGY` 尚未存在（因 `evaluate` 里 `w3` 仍硬编码 0），所以哈希无法区分"energy 是否真参与"——一旦未来接入 `W_ENERGY`，必须同步进哈希，否则不同 energy 配置的导出 JSON 会哈希撞车、不可溯源。

4. Pareto 冗余已清理（`Z/mk_n/lb_n` 删除，仅留 mk/lb/obj3），这是正确修复。但 `build_pareto`（两目标分支）仍构造 `obj3 = [Zsel, NaN]`，而三目标分支 `obj3 = [mk_n, ld_n, en_n]`——两分支 obj3 前两列含义不同（一是归一化加权和分量、一是归一化 mk/ld），前端 `make_pareto_figure` 取 `obj3[:,2]` 作 energy 色轴在两目标时全 NaN 被正确处理，但"obj3"这个统一字段承载了两种不同语义，长期维护易踩坑。建议两目标分支 obj3 也统一为 `[mk_n, ld_n]`（无 energy 维），与三目标分支前两列对齐。

5. 时间戳文件名 `results_<timestamp>.json` 每次运行生成新文件，无覆盖/归集机制，`logs/results/figures` 下会累积大量文件，概览表会因历史文件堆积而变长且混显。建议加 run 标签或结果归集目录。

## 五、总体结论与优先级

项目工程纪律（零回归、ADDITIVE、契约化、可复现 seed/cfg_hash）是其最强项，证据链（stage7 基准 + SOTA Wilcoxon）已具备投稿雏形。但**投稿级硬伤集中在三处**：

- P0（阻塞投稿）：联网 LLM 增益仍为 0（缺 Key/网络），双引擎贡献无量化证据；旧归一化 `tevc_submission` JSON 必须重导出。
- P1（定位诚实性）：三目标 energy 第三维退化（w3 恒 0）+ NSGA-III 主选默认关，"伪三目标"需在正文诚实定位或真正接入 `W_ENERGY`。
- P2（稳健性）：大/难实例 MK02/06/09 偏弱需补强或诚实讨论；动态场景主链未启用，不能宣称为主引擎能力；收敛 std 带默认空、概览表语义混用、旧格式 JSON 混入发现。

可视化与存储整体可用、已修复主要 bug，剩余问题均为"展示严谨性/可维护性"层级，不阻塞功能，但建议在投稿前清理旧归一化 JSON、统一 obj3 语义、明确概述表列义、把多 run 方差导出纳入默认或文档化。

## 参考文件
- `llmaoo_config.m`、`llmaoo.m`、`aoo_engine.m`、`evaluate.m`、`decode.m`
- `benchmarks/define_problem.m`、`benchmarks/attach_stage8.m`
- `exports/export_result_json.m`、`viz/dashboard.py`、`viz/plotly_convergence.py`、`viz/digital_twin.py`
- `logs/stage7_benchmark.json`、`logs/stage7_sota.json`、`results/tevc_submission/tevc_full_result.json`
