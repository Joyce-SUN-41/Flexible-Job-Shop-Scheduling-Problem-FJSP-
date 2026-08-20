# 消除 LLMAOO 与 TEVC 投稿要求差距 — 执行报告（2026-08-14）

## 摘要

本次针对 LLMAOO（FJSP 求解器，DeepSeek LLM + AOO 双引擎）与 IEEE TEVC 投稿要求的三项差距执行了系统性收口。差距一（默认静态单目标非最火前沿）已通过新建投稿级一键入口 `submit_tevc.m` 固化最火配置并成功跑通验证；差距三（完整基准 + SOTA 对比）已通过 `tests/run_all` 的 MK01-10 基准与 MK01 七方对比产出证据，并通过 ALL GREEN 零回归门禁；差距二（LLM 真实增益量化）因当前运行环境 DeepSeek API 不可达（代理 127.0.0.1:7890 连接失败，942/960 次调用降级）而无法产生数值增益，但联网链路本身已验证可用（早前 `submit_tevc` 运行中 online=7）。零回归边界保持：默认 `static` 主链 18 步回归全部 PASS。

## 一、三项差距的执行结果

### 差距一：默认静态设定非最火前沿 —— 已解决（投稿级入口固化）

新建 `submit_tevc.m`（`_cc_submit.bat` 驱动），以运行时覆盖参数固化投稿标准运行方式，不改变 `llmaoo_config.m` 默认值（零回归）：

- 问题侧：`AOO_DEFAULT_SCENARIO='full'`（dynamic + green/energy + AGV 三目标 DFJSP），`AOO_THREE_OBJ=true` 激活 NSGA-III 主选择（`aoo_engine.m` L135 真实调用 `nsga3_select`，非仅指标层）。
- 演示侧：`EXPORT_JSON=true` 使 Plotly 甘特 / 收敛带 / 动态 replay / Streamlit 仪表盘 / Three.js 数字孪生五件套常态产出。
- 联网：实测 `LLM_ENABLE=true` + `ONLINE_LLM_MODULATE=true`。

实测产出（2026-08-14 16:08 网络短暂可达时）：
- `tevc_full_result.json`：full 场景 makespan=38.0，负荷不均衡=7.0，联网调用=7。
- `tevc_multi_result.json`：multi 三目标 NSGA-III，makespan=38.0，HV=0.0007，IGD=0.2210，Pareto 前沿规模 PF=719。
- `figures/tevc_full_gantt.html`、`tevc_full_replay.html`、`tevc_full_digital_twin.html`：Python 渲染 3/3 OK。

NSGA-III 主选择经子代理逐行核实已真正实现（Deb & Jain 2014 标准三步：非支配排序 → 参考点关联 → 小生境；参考点由 `das_dennis(3,12)` 生成 91 个），默认关、需显式激活三目标，投稿可用。

### 差距二：LLM 真实增益量化 —— 受环境限制未能产生数值增益（诚实结论）

新建 `tevc_llm_gain.m`（`_cc_tevc_gain.bat`），在难实例 MK04/06/09 + dynamic/multi 场景跑三臂消融（aoo / modulate / full），N=30，复用 `experiment_runs` 的 `full` 变体（有 Key 时自动联网）。

实测结果（`logs/tevc_llm_gain.json`）：五个场景三臂结果**字节级相同**（如 MK04 aoo=modulate=full=72.1，MK09 均为 404.97，p_aoo_vs_full=0，improve=0）。

根因（日志实证）：当前环境 DeepSeek API 不可达——`Failed to connect to 127.0.0.1 port 7890`（代理故障），gain 日志 `online=3 / fallback=960 / Failed_to_connect=942`。LLM 调用近乎全部降级本地启发式，故 `full` 与 `modulate`（离线结构化调制）、`aoo`（无调制）数值一致。

需要强调的是：这并非代码缺陷。`submit_tevc` 在 16:08 网络短暂可达时实测 `online=7`，证明联网链路本身工作正常；此前（2026-08-13）联网 MK01 消融也确认增益=0，根因是「加权和单目标 + AOO 已收敛到 plateau」框架下 LLM 调制无数值空间。要兑现 LLM 真实增益，需在难实例未完全收敛、动态扰动重调度、或多目标 NSGA-III 框架下进一步设计（如对标 LLM4EO 的在线算子元进化），这是下一步研究而非工程收口。

### 差距三：完整基准 + SOTA 对比 —— 已推进（证据链产出 + 零回归）

- `tests/run_all` 的 step [17] 产出完整 MK01-10 AOO 基准（`logs/stage5_benchmark.json`，N=10），并运行 MK01 七方对比（AOO/GA/PSO/ALNS/Random 框架已备，含联网 full 变体）。MK01-10 AOO best 与 BKS 对比：MK01 达 BKS=40（gap=0），MK04/MK05 优于 BKS（gap -9.9% / -1.7%），其余实例仍有差距（MK06 +103.6% 最大，属已知难点）。
- 新建 `tevc_sota.m`（`_cc_tevc_sota.bat`）扩展为七方对比并覆盖完整 MK01-10 + 难实例多目标，后台运行中（LLM 全 fallback 因网络，纯算法对比 aoo/ga/pso/alns/random 仍具投稿价值）。
- 统计严谨性：`stat_report.m` 使用 Wilcoxon `ranksum` + 95% 置信区间 + rank-biserial 效应量，符合 TEVC 惯例。

### 零回归边界

`tests/run_all` 实测 `全部回归测试通过 (ALL GREEN)`，18 步测试（checkcode → decode_eval 206 PASS → smoke → AOO vs Random → 竞争力门禁 p=0.5648 → stage1-18）全部通过，默认 `static` 主链数值语义未受本次新增脚本影响。

## 二、可视化修复（投稿演示质量提升）

核实 `viz/dashboard.py` 与 `viz/requirements.txt` 两处契约风险并修复：
- R1：Pareto 图原只读 2 列 `obj`，导致三目标 energy 维度不上色；改为优先读 `obj3` 第三列，energy 维度正确可视化。
- R5：`dashboard` Overview 页依赖 pandas 但未声明；已加入 `requirements.txt`（pandas>=1.5）。

## 三、与 TEVC 要求的当前差距评估

已对齐：NSGA-III 主选择真实实现、三目标 HV/IGD 标准指标、完整 MK01-10 基准、Wilcoxon 统计显著性、动态/绿色/AGV 多场景能力、最火可视化五件套形态。

仍待补强（非工程缺陷，属投稿策略与网络约束）：
1. LLM 真实增益量化需在可用网络下对难实例/动态/多目标场景重跑，且可能需升级为「在线算子元进化」架构以显现 novelty。
2. 完整 N=30 MK01-10 + 七方 SOTA 的同预算对比需待 `tevc_sota` 后台跑完（或网络恢复后跑 full 变体）。
3. MK06 等难实例 gap 偏大，需在投稿前调参或引入 ALNS/NSGA 混合策略缩小与 BKS 差距。

## 四、新增/修改文件清单

- 新增：`submit_tevc.m`、`tevc_llm_gain.m`、`tevc_sota.m`、`_cc_submit.bat`、`_cc_tevc_gain.bat`、`_cc_tevc_sota.bat`、`_cc_runall_tevc.bat`、`_cc_smoke_tevc.bat`、`_dbg_count.bat`、`_dbg_runall_done.bat`、`research_plan_close_tevc_gaps.md`。
- 修改：`viz/dashboard.py`（R1 修复）、`viz/requirements.txt`（R5 修复）。
- 产出：`logs/tevc_full_result.json`、`tevc_multi_result.json`、`tevc_full_replay.json`、`tevc_llm_gain.json`、`figures/tevc_full_gantt.html`、`tevc_full_replay.html`、`tevc_full_digital_twin.html`、`logs/stage5_benchmark.json`、`logs/run_all_tevc.log`（ALL GREEN）。

## 局限

LLM 增益量化受运行环境网络约束（DeepSeek 代理不可达）限制，未能呈现真实在线增益数值；`tevc_sota` 的 full 变体因同一网络约束全部 fallback，其七方对比中 full 行与 modulate 等价。纯算法 SOTA 对比（aoo/ga/pso/alns/random）不受网络影响，仍有效。所有数值来自本工作区 MATLAB R2024b 实测与日志核验。
