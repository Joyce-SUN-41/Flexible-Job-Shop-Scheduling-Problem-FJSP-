# LLMAOO 项目体检报告 — 问题侧 / 方案侧 / 可视化 / 结果存储

检查日期：2026-08-18。本次为静态代码审查 + 产物抽样，未重新运行求解（遵循"不擅自启动进程"原则）。覆盖 `llmaoo.m`、`aoo_engine.m`、`evaluate.m`、`benchmarks/define_problem.m`、`exports/*.m`、`viz/*.py`、`README.md` 以及 `results/`、`logs/` 产物。

## 一、问题侧评价（FJSP 建模与评估）

问题建模整体是标准 FJSP：工序可选机器、最小化 makespan + 机器负荷不均衡度，可选第三目标能耗。三个层面评价：

建模正确性较好。解码层 `decode_X` 与全部邻域算子（风/水/动物/滚动/弹射）对"工序序号 = OS 前缀累加计数"的处理已经统一（MEMORY 记录的历史坑 `prob.opOf(t)` 误用已修复），`fix_os_counts` 也保证了染色体工序守恒，这是早期 MK04/05/08 越界崩溃的根因，现已闭合。

目标归一化做得合理但有隐患。`evaluate.m` 用固定理论上界 `prob.mk_ub` 归一化 makespan 与 loadUnb 到 [0,1]，解决了"makespan(~200) 量级淹没 loadUnb(~30)"导致双目标加权和实质退化为单目标的问题，这是真实且有价值的修正。但**负荷不均衡度用同一个 `mk_ub` 做分母**在语义上是可疑的：`loadUnb` 的物理上界应当是 `max(loadVec) - min(loadVec)` 的可能最大值，而非 makespan 上界；用 `mk_ub` 归一化会让 `loadUnb` 落在远小于 1 的小区间，两目标加权后 loadUnb 的边际贡献被人为压低，使"负荷均衡"这一宣称目标在数值上仍偏弱。这是建模层面需要正视的点，而非实现 bug。

能耗第三目标（green/multi）修复是实质性的。`attach_energy` 用固定理论界 `e_ub = Σ max_m能耗` 替代旧版 `1.5*energy+1` 自适应渐近线，消除了 obj3 第三维恒塌缩到 0.6645 的退化；`evaluate` 仅在 `numel(w)>=3` 时取 `w3`，保证默认两目标零回归。这部分逻辑自洽。

弱实例是真实的竞争力短板。阶段三.1 实测 MK02(+26.9%)/MK06(+65.5%)/MK09(+7.7%) 相对 BKS gap 大，且增强局部搜索探索（`stage7_strong_x3.m`）结论不可靠（激进版 MK02 改善但保守版退化），项目以 Limitations 诚实讨论而非伪装调参，做法正确。但需注意：energy 第三维仅在 MK01 等小规模实例验证，大实例的多目标竞争力未被系统量化，投稿多目标 rigor 的证据链在大实例上仍空。

## 二、方案侧评价（LLMAOO 双引擎）

方案新颖性定位清晰：LLM(DeepSeek) 契约解析 + AOO 五策略离散邻域双引擎。四个亮点：

离线可跑的诚实降级设计是工程亮点。`deepseek_chat.m` 在无 `DEEPSEEK_API_KEY` 时自动降级本地启发式，`tevc_llm_gain.m` 以 `full≡modulate` 诚实固化离线态（增益=0 是环境事实而非代码缺陷），`env_manifest` 显式标记边界。这对 TEVC 投稿的"可复现性"是加分项。

LLM 三增益链路已闭合。历史上 `explore_bias` 是唯一未被算子消费的增益，现已接入 `windPm`，使 LLM 真正影响全部五策略。系数是外部调制（仅缩放强度不改结构），双引擎"LLM 指导 AOO"的叙事自洽。

NSGA-III 主选择修复是真实的。旧代码在 NSGA-III 分支传 `[1 1]` 两元素权重，导致 `evaluate` 走 else 返回 2 维、energy 第三列恒为 0，是"伪三目标"的另一根因；现传 `[1 1 1]` 触发三目标分支，`aoo_engine` 用 NSGA-III 非支配排序 + 参考点小生境真正替主链选 N 个个体，门禁 [10] 端到端验证 HV/IGD 有限非负。这部分从"伪多目标"升级为"真实三目标主选"，是投稿严谨性的关键补强。

需要警惕的方案风险：(1) **联网 LLM 真实增益至今为零证据**。所有 SOTA 对比（stage7_sota、stageB_sota）的"baseline 增益"实际来自 `offline_structured_modulate`，而非联网 LLM；论文若把 LLM 引擎的贡献表述为"DeepSeek 在线增益"会越界，目前 README 已诚实限定为可复现代理，但正文叙事易踩线。(2) **停滞重启与精英注入是通用 GA 机制**，AOO 五策略与标准 GA/PSO 的差异化竞争力在 stageB_sota 中 GA/PSO 被投影为单点 PF 后与 AOO 多点 PF 对比，HV 天然占优 AOO，这个对比口径虽诚实标注，但易被审稿人质疑"对比不公平"。(3) AOO 算法本身（动麦种子传播）与 FJSP 的映射是工程化的隐喻映射，novelty 在"LLM 契约引导"而非 AOO 本身。

## 三、可视化设计检查

四个可视化脚本（dashboard.py / plotly_gantt.py / plotly_convergence.py / digital_twin.py）均为"只读 JSON、零回归"的 ADDITIVE 设计，契约兼容层做得到位（`_normalize_schedule` 同时兼容 array-of-arrays / list-of-dicts / MATLAB struct-array；`make_pareto_figure` 显式 `energy_n` 优先 + `obj3[:,2]` 回退），鲁棒性好。

发现的问题：

收敛曲线真实刻度修复是正向的（`trace_makespan` 替代归一化 `trace_best`），dashboard 与 `plotly_convergence.py` 都优先读真实 makespan，避免读者把 0.x 当真实刻度。

但是存在**一处前端/契约语义错位**：`dashboard.py` 的概览表 `make_overview_table` 把 SOTA 对比行的 `final_best` 取为 `max(mk[vn])`（最差值），注释写"同表统一为求得值"，但 benchmark 行的 `final_best` 取 `aoo_best`（最优值），两行对 `final_best` 的语义不一致（一为最优一为最差），且列说明注释只解释了 benchmark 行，SOTA 行的反向语义未声明，易误导。

`digital_twin.py` 的 Z 轴作业分层修复（原 `*0.0` 笔误）已落地，但 3D 中 `laneDepth*1.6` 间距与 box 深度 `d=4` 在多作业实例下可能重叠，属展示瑕疵非错误。

`replay` 契约对称性良好：`export_replay_json` 写 `kind=='dynamic_replay'` + 非空 `frames`，`digital_twin.py` 与 `dashboard` 均按此路由，门禁 [4] 也校验。

## 四、结果存储设计检查（重点问题区）

存储契约设计理念正确：`contract_version` 版本化、`cfg_hash` 可复现追踪、`EXPORT_DIR` 聚合、默认 `EXPORT_JSON=false` 零回归。但检查发现**真实的存储治理缺陷**：

**核心缺陷：代码契约版本(1.2)与产物契约版本(1.1)严重脱节。** `exports/export_result_json.m` 第 21 行已写 `out.contract_version = '1.2'`，README 阶段四 P2 明确"契约升 1.2 + 显式 `energy_n` 字段"，stage9_run 门禁 [4/5] 也断言 `contract_version >= '1.2'`。然而 `results/` 根目录下 32 个 `results_*.json` 全部是 `"contract_version": "1.1"`，`results/tevc_submission/` 下 `tevc_full_result.json` / `tevc_multi_result.json` 也是 `"1.1"`。这说明：要么导出脚本当前实际跑的不是 1.2 代码（代码与运行环境版本不一致），要么 1.2 改动后从未重跑导出。无论哪种，`dashboard.py` 的契约版本告警逻辑 `if cv is None or str(cv) < "1.1"` 对 1.1 不报错、对 1.2 才是"新契约"，但**前端按 1.2 读 `energy_n` 字段，而 1.1 产物根本没有 `energy_n`**（仅 stage9_run 的测试桩构造了空 energy_n），导致 1.1 产物在 Pareto 页能量色轴回退用 `obj3[:,2]` 旧路径——这与"1.2 解耦 energy_n"的设计意图矛盾。这是必须修复的：重跑导出使产物与代码契约一致，或回退代码到 1.1 口径。

**存储散落与重复。** `results/` 根目录散落 34 个带毫秒时间戳的 `results_*/replay_*.json`（2026-08-17~18 多次调试遗留），`logs/` 另有 64 个文件（48 .log + 16 .json），`figures/` 与 `results/tevc_submission/` 又各存一份插图/JSON。README MEMORY 已记录"用户拒绝清理 stray 时间戳文件（无害）"，但投稿前这些散落文件会污染可复现性包，且 dashboard 的 `discover_results` 会递归扫描所有目录，把调试产物也纳入概览表，造成概览表噪音。建议：导出统一进 `results/<scenario>/` 子目录（代码已支持 `EXPORT_DIR`），根目录时间戳文件迁移或归档。

**密钥/环境诚实态未与产物绑定。** `env_manifest.json` 在 `results/tevc_submission/` 下，但主 `results/*.json` 顶层没有 `env_state` / `llm_online` 字段绑定。一个第三方拿到 `results_2026_08_18_09_23_14.json` 无法从该文件本身判断是否联网 LLM 产物；`result.llm_counts` 字段在导出脚本 `export_result_json.m` 中**根本未被写出**（只写了 `quality`/`pareto`/`schedule` 等），导致离线诚实态无法从 JSON 反推。这是存储设计与"诚实声明"目标之间的脱节。

**收敛 std 带默认不可用属设计妥协，非缺陷。** `EXPORT_CONV_JSON` 默认 false，单次运行不写 `conv_*.json`，dashboard/plotly_convergence 的 mean±std 带为空。README 已声明这是零回归安全默认，启用需 `_cc_conv_batch.bat`。但副作用是：默认产物无法支撑"均值±标准差收敛带"这一 TEVC 常见投稿图，需显式批量导出。建议投稿图中明确标注哪些图来自批量独立 run 而非单次。

## 五、综合结论与建议

项目在工程严谨性（离线降级、契约版本化、零回归、NSGA-III 真三目标、历史崩溃坑修复）上达到投稿级水准，问题侧建模正确、方案侧双引擎叙事自洽。主要风险不在算法而在**存储/契约治理与证据诚信闭环**：

1. 立即修复契约版本脱节：用当前 1.2 代码重跑 `submit_tevc_offline.m` 重导出 `tevc_submission` 全部 JSON，并清理或与代码对齐版本号（否则前端 energy 色轴逻辑与产物不符）。
2. 在 `export_result_json.m` 顶层补写 `env_state`（online_real / offline_honest）与 `llm_counts`，使每个 JSON 自带诚实态，支撑可复现性审核。
3. 统一导出目录，归档 `results/` 根目录 34 个散落时间戳文件，避免 dashboard 概览噪音。
4. 正视 loadUnb 用 `mk_ub` 归一化导致的双目标失衡隐患，投稿前做一次敏感性分析（W_LOAD 不同取值下 loadUnb 改善幅度）。
5. 联网 LLM 增益在拿到 Key+网络前，正文仅声明离线结构化调制贡献，不越界。

## 参考文件
- `c:\Users\Joyce_SUN\Desktop\FJSP\README.md`
- `c:\Users\Joyce_SUN\Desktop\FJSP\exports\export_result_json.m`（contract_version=1.2）
- `c:\Users\Joyce_SUN\Desktop\FJSP\results\results_2026_08_18_09_23_14.json`（契约 1.1，与代码脱节）
- `c:\Users\Joyce_SUN\Desktop\FJSP\results\tevc_submission\tevc_full_result.json`（契约 1.1）
- `c:\Users\Joyce_SUN\Desktop\FJSP\viz\dashboard.py`（Pareto 页 energy_n 读取逻辑）
- `c:\Users\Joyce_SUN\Desktop\FJSP\evaluate.m`（归一化与三目标分支）
- `c:\Users\Joyce_SUN\Desktop\FJSP\aoo_engine.m`（NSGA-III 主选择分支）
