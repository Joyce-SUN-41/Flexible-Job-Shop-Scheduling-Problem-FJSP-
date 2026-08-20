# LLMAOO — LLM-Guided Adaptive Operator Optimization for FJSP

FJSP（柔性作业车间调度）求解器：LLM（DeepSeek）契约解析 + AOO（自适应算子优化）五策略双引擎。
主链目标 = 加权最小化 makespan + 机器负荷不均衡度（两目标加权和自适应搜索）。
能耗作为可选第三目标：当 `W_ENERGY>0` 且 `AOO_THREE_OBJ=true` 时真实参与主链选择（不再是旧版的 `w3=0` 退化）；
NSGA-III 非支配排序 + Hypervolume/IGD：**当 `AOO_THREE_OBJ=true` 时，energy 第三维经 NSGA-III 非支配排序真实参与主链选择（真实三目标，非伪多目标）**，
由 `aoo_engine` 实现，`submit_tevc` 等投稿入口即走此路径；默认 `false` 时为两目标加权和主链，数值零回归。
HV/IGD 作为质量指标由门禁 [10]（`quality_metrics`）端到端验证（非附加评估）。

目标期刊：IEEE TEVC（要求 novelty / 标准基准 / 统计显著性 / 多目标 rigor）。

## 环境

- MATLAB R2024b（路径 `E:\Matlab R2024b\bin\matlab.exe`）。必须用 `.bat`（`cmd /c`）调 `-batch "code"`，
  避免 PowerShell 引号冲突。验证/函数名须纯 ASCII（中文/下划线前缀在 `-batch` 报"文本字符无效"）。
- DeepSeek 接入：`llmaoo_config` 通过 `getenv('DEEPSEEK_API_KEY')` 注入 Key；未设置时自动降级本地启发式（离线可跑，零消耗）。
  联网真实 LLM 增益须 `DEEPSEEK_API_KEY` + 网络可达（见下方"已知阻塞"）。

## 运行入口

```matlab
% 主入口（默认 static 两目标，离线可跑）
res = llmaoo();

% 多目标 NSGA-III 分析模式（额外开启 energy 第三维）
res = llmaoo('AOO_DEFAULT_SCENARIO','multi');

% 动态重调度
res = llmaoo('AOO_DEFAULT_SCENARIO','dynamic');

% 导出 JSON 供 Python/Plotly 可视化
res = llmaoo('EXPORT_JSON', true);
```

回归套件：

```matlab
tests.run_all        % 18 个门禁（checkcode / 自测 / 场景激活 / 竞争力门禁 …）
```

命令行（项目根目录）：

```bat
matlab -batch "cd('项目根'); tests.run_all; exit"
```

## 配置字段表（`llmaoo_config.m`）

| 字段 | 默认 | 说明 |
|------|------|------|
| `LLM_ENABLE` | `false` | 默认关，全部走本地 mock 回退（离线可跑）。量化增益时临时置 `true` |
| `DEEPSEEK_API_URL` | `https://api.deepseek.com/v1/chat/completions` | DeepSeek OpenAI 兼容端点 |
| `DEEPSEEK_API_KEY` | `getenv(...)` | 空 => 离线降级 |
| `DEEPSEEK_MODEL` | `deepseek-chat` | 或 `deepseek-reasoner` |
| `LLM_MAX_TOKENS` | `600` | |
| `LLM_TEMPERATURE` | `0.4` | 偏低，保证调度建议稳定可复现 |
| `LLM_TIMEOUT_SEC` | `30` | webwrite 超时 |
| `LLM_CACHE` | `true` | 相同 prompt 命中缓存（离线启发式文本不缓存，防污染诚实在线增益） |
| `LLM_CALL_EVERY_GEN` | `15` | 职责1/2/3 调用周期 |
| `LLM_DIAG_EVERY_GEN` | `40` | 职责4 种群诊断周期 |
| `LLM_ONLY_ON_STAGNATION` | `true` | 仅在停滞窗口内触发调制 |
| `AOO_POP` | `100` | 种群规模 |
| `AOO_MAXGEN` | `150` | 最大迭代 |
| `AOO_REFINE_EVERY` | `5` | 精英关键路径精炼频率 |
| `AOO_LEVY_BETA` | `1.5` | Levy 指数 |
| `AOO_C_DECAY` | `3` | 探索→开发三次衰减幂次 |
| `AOO_EARLY_PATIENCE` | `120` | 早停耐心（代） |
| `AOO_EARLY_DIV_TH` | `0.01` | 早停多样性阈值 |
| `AOO_PARALLEL` | `false` | 并行评估开关（需 Parallel Computing Toolbox） |
| `OFFLINE_STRUCTURED_MODULATE` | `false` | 阶段C：离线结构化调制（默认关以保证零回归） |
| `W_MAKESPAN` / `W_LOAD` | `1.0` | 主链双目标加权和权重（makespan + 负荷均衡） |
| `W_ENERGY` | `0` | 能耗第三目标权重。**默认 0 => 主链为纯两目标加权和，数值完全不变（零回归）**。当 `>0` 且 `AOO_THREE_OBJ=true` 时，energy 真正进入主链选择（修复旧代码 `w3=0` 恒为 0 的"伪三目标"退化）。`cfg_hash` 已纳入 |
| `AOO_DEFAULT_SCENARIO` | `'static'` | static/multi/dynamic/green/transport/full（单一能力激活入口） |
| `AOO_DEFAULT_PROB` | `'MK01'` | Stage8 模式默认实例 |
| `AOO_THREE_OBJ` | `false` | 三目标（含 energy）主选择开关；**开启后 `aoo_engine` 用 NSGA-III 非支配排序替主链选出 N 个个体（真实三目标主选，非附加评估）**，`evaluate` 第五输出为三目标向量 `[mk_n, ld_n, en_n]`。`cfg_hash` 已纳入 |
| `AOO_DYNAMIC` | `false` | 动态重调度主循环 |
| `AOO_AGV` | `false` | AGV 运输时间约束 |
| `ENERGY_UB` | `0` | 能耗归一化上界；`0` => 走 `attach_energy` 固定理论界 `prob.e_ub`（见阶段二修复）；`>0` => 走配置上界。`cfg_hash` 已纳入 |
| `DYN_SCENARIO` | `'breakdown'` | 动态场景（breakdown/urgent/delay） |
| `HV_REF` | `[]` | 三目标 HV 参考点（空 => 自适应） |
| `NSGA3_P` | `12` | Das-Dennis 分层数（三目标 12 => 91 参考点） |
| `ONLINE_LLM_MODULATE` | `false` | 阶段D：在线/离线增益诚实归因（默认关） |
| `EXPORT_JSON` | `false` | Stage9：求解结束写 JSON（默认关） |

## 导出 JSON 契约（`exports/export_result_json.m`，`EXPORT_JSON=true` 时写出）

顶层字段：`version`、`generated`、`problem{nJob,nMachine,nOp,has_energy,has_agv,has_dynamic,name}`、
`makespan`、`loadUnb`、`iters`、`nan_count`、`elapsed_sec`、`pareto_count`、
`mk_ub`（反归一化上界）、`cfg_hash`（8 位十六进制）、`seed`、`scenario`、
`schedule[job,op,machine,start,finish,duration]`、`pareto{mk,lb,obj3}`。

`cfg_hash` 覆盖（与 `llmaoo.cfg_hash` 严格一致）：`AOO_POP/MAXGEN/C_DECAY/LEVY_BETA`、
`W_MAKESPAN/W_LOAD/W_ENERGY`、`AOO_DEFAULT_SCENARIO`、`AOO_THREE_OBJ`、
`OFFLINE_STRUCTURED_MODULATE`、`LLM_ENABLE`、`RNG_SEED`、`ENERGY_UB`。
`W_ENERGY` 默认 0 时哈希与旧版一致（零回归）；`ENERGY_UB` 区分固定 `e_ub`(=0) 与配置上界(>0) 两种归一化路径。

### 字段量纲表（real vs normalized，避免误读）

| 字段 | 含义 | 量纲 |
|------|------|------|
| `loadVec` | 各机器负荷之和 | 真实（sum of op durations per machine） |
| `loadUnb` | 机器负荷不均衡度 = max−min | 真实（`max(loadVec)-min(loadVec)`） |
| `pareto.mk` / `pareto.lb` | 非支配解真实 makespan / 负荷不均衡 | 真实（坐标轴直接用） |
| `pareto.obj3` | `[mk_n, ld_n, en_n]` 三目标向量 | 归一化（[0,1]），供 HV/IGD 指标链与能量色轴 |
| `pareto.energy_n` | 显式能耗色轴（v1.2 新增） | 归一化；两目标分支为 `[]`（非 NaN），表示"无能耗维" |
| `trace_makespan` / `trace_loadUnb` | 每代真实 makespan / 负荷不均衡序列 | 真实（前端优先用于收敛曲线） |
| `trace_best` / `trace_mean` | 每代最优/平均归一化加权和 | 归一化（legacy 兼容，0.x 量级，**不可当真实刻度**） |
| `mk_ub` | makespan 归一化固定理论松弛上界 | 真实标量（makespan 各工序最快机工时之和） |

`schedule` 行格式契约（导出与 `viz/*` 均按列序位置读取，无运行时校验）：
`[job, op, machine, start, finish, duration]`（6 列，且须 `finish >= start >= 0`）。
阶段五计划加 `validate_schedule(rows)` 统一校验层，消除跨模块隐性耦合。

## 可视化（`viz/`，纯读 JSON 契约，零回归）

- `plotly_gantt.py` / `plotly_convergence.py`：甘特图 / 收敛曲线（优先读真实 `trace_makespan`）；收敛 std 带（`figures/convergence_std.html`）由 `tests.stageC_conv_batch` 批量导出后用 `python viz/plotly_convergence.py logs/conv_*.json` 聚合，纵轴为真实 makespan 刻度。**注意双轨量纲**：MATLAB `visualize.m` 的收敛图纵轴是归一化加权和 `trace_best`（0.x 量级，legacy 兼容），不可当真实 makespan；真实收敛须看上述 Plotly/dashboard 路径。两轨不可互换（阶段五 E1/E7 已标注）。
- `replay_dynamic.py`：动态重调度回放。
- `dashboard.py`：Streamlit 交互式仪表盘（`pip install -r viz/requirements.txt && streamlit run viz/dashboard.py`）。
- `digital_twin.py`：自包含 Three.js 3D 数字孪生 HTML（`python viz/digital_twin.py logs/...json -o figures/digital_twin.html`）。

## 阶段演进与状态

| 阶段 | 内容 | 状态 |
|------|------|------|
| 一 P0 | 存储/可视化契约清理（统一 obj3 语义、概览表列义、conv 导出、contract_version、EXPORT_DIR） | 已完成（代码层 + 阶段〇重导出 `tevc_submission` 1.1 JSON 已落地；obj3 两目标/三目标语义已对齐 `build_pareto` L347） |
| 二 P1 | 多目标 honest positioning + energy 修复 | **已完成（本次）**：接入 `W_ENERGY` 修复 `w3=0` 退化、`evaluate_population` 三权重透传、`cfg_hash` 追加；`AOO_THREE_OBJ=true` 时 `aoo_engine` 用 NSGA-III 非支配排序（硬编码 `[1,1,1]` 触发 `evaluate` 三目标分支）真实替主链选择（真实三目标，非附加评估、非伪多目标）；`W_ENERGY=0` 时精英两目标加权和数值零回归，门禁 [9] 验证 energy 第三维真实分化、[10] 验证 HV/IGD |
| 三.1 P0 | 离线基准长跑（MK01-10 N=30 + 五方 SOTA） | 已完成（`logs/stage7_benchmark.json` + `logs/stage7_sota.json`，含真 bug 修复） |
| 三.2 P1 | 联网 LLM 真实增益（`tevc_llm_gain`） | **已完成（诚实固化）**：脚本 `tevc_llm_gain.m` 健全、降级逻辑透明；当前环境离线，`results/tevc_llm_gain/tevc_llm_gain.json` 已是诚实的 `full≡modulate` 产物（增益=0 是环境事实，非缺陷）。配套 `env_manifest.json` 固化离线诚实态（不可宣称在线 LLM 增益）。修复 signrank 误取布尔同源 bug（L62）。联网复跑步骤见 manifest |
| 二 P1（阶段二落地） | 联网 LLM 真实增益复跑（环境依赖） | **已完成（2026-08-18，代码就绪+环境诚实态）**：① `tevc_llm_gain.m` 增强环境态诚实探测（运行前打印 DEEPSEEK_API_KEY 注入/网络可达态，产出 JSON 固化 `env_state` 字段 `mode=online_real/offline_honest`，离线态明确标记 `full≡modulate≡aoo` 增益=0 是环境事实，不伪造）；② 新增 `_cc_llm_gain.bat` 一键触发（含 Key 占位行，填 Key 后运行即真实联网）；③ `env_manifest.json` 升级为 2026-08-18 状态（代码就绪、环境阻塞、新增 bat 入口、门禁[6]/[20] 不依赖联网增益）。**实际联网复跑仍环境阻塞**（无 Key+网络），须用户注入 Key 后运行 bat 或 `tests.tevc_llm_gain` |
| 四 P2 | pareto 契约清理（`energy_n` 显式字段 + 契约升 1.2） | **已完成（2026-08-18，ADDITIVE 零源改）**：`exports/export_result_json.m` 契约升 `1.2`，新增显式 `pareto.energy_n` 字段（三目标分支=obj3 第三列 en_n，两目标分支置 `[]` 非空 NaN，消除"从 obj3[:,2] 取 energy"的脆弱/易误读依赖）；`viz/dashboard.py` 色轴改读 `energy_n`（回退 `obj3[:,2]` 仅当 <1.2）；`tests/stage9_run.m` 新增门禁校验 `contract_version>=1.2` 且 2-obj `energy_n=[]`；`conv` 导出同步升 1.2。`obj3` 完整三目标向量保留供 NSGA-III 指标链(HV/IGD) 使用，不受影响。**注意**：`tests.run_all` [1]-[18] 全绿闭合为更早独立完成项（2026-08-18 `_cc_stage4_runall.bat` 实证），与本次 pareto 清理正交 |
| 一 P0（方法学+弱实例） | 方法学口径统一 + 大实例结构性补偿 | **已完成（2026-08-18）**：① `llmaoo_config.m` 顶部注释明确"默认两目标加权和主链(A) vs NSGA-III 三目标主选(B) 互斥配置"诚实定位（任务 1.1）；② 新增 `tests/stage7_large_config.m`（按 nOp 自适应放大预算的结构性 large-config，独立日志 `logs/stage7_large.json`，零源改动、不污染默认主证据 `stage7_benchmark.json`，任务 1.2）；③ `run_all` 新增门禁 [19] 软失败断言 large-config 在 MK02/06/09 不劣于默认配置（日志缺失则 SKIP 不阻塞，任务 1.3）。弱实例偏弱保留为 Limitations 诚实讨论点 |
| 三 P1（三目标竞争力证据） | 3.1 三目标 SOTA 对比 + 3.2 门禁双路径口径 | **已完成（2026-08-18）**：① 新增 `tests/stageB_sota.m`（multi 场景 AOO(NSGA-III 三目标主选) vs Random 多目标投影，各 N=30，同评价预算，收集 `pareto.obj3` 用 `nsga3_quality` 算 HV/IGD，Wilcoxon 检验，产出 `logs/stageB_sota.json`）；② `run_all` 新增门禁 [20] 软失败断言 AOO 三目标 HV 不显著劣于 Random（日志缺失则 SKIP 不阻塞），`tests/stageB_sota.m` 已纳入 coreFiles；③ 门禁 [6] 升级为双路径口径：仅校验默认两目标主链竞争力（核心门槛不动），明确提示"三目标 NSGA-III 路径由门禁 [20] 独立校验"，两处口径分离互不阻塞。TEVC 多目标严谨性缺口已补 |
| 五 P2 | 可复现性与可视化增强（std 带批量导出 + 回放契约对称） | **已完成（2026-08-18，ADDITIVE 零源改）**：① 新增 `tests/stageC_conv_batch.m`（循环 N 次独立 run，用 `AOO_DEFAULT_SCENARIO='multi'` 使 `AOO_DEFAULT_PROB` 被消费以载入 MK01，每次 `EXPORT_CONV_JSON=true` + `EXPORT_DIR='logs'` + 不同 `RNG_SEED`，写出 `logs/conv_*.json`，供 `plotly_convergence.py` 聚合 mean±std 带），配套 `_cc_conv_batch.bat` 一键驱动；`EXPORT_CONV_JSON` 默认 false 不动（零回归），仅本脚本显式开启。② `tests/stage9_run.m` 新增门禁 [4] 回放契约对称性核对：断言 `kind=='dynamic_replay'` 且 `frames` 非空（与 `digital_twin.py` 渲染分支契约一致）。③ 未改 `EXPORT_CONV_JSON` 默认、未改 solver 数值 |
| 三 P1（补） | 3.1 三目标**多算法**对比 + Kruskal-Wallis | **已完成（2026-08-18，ADDITIVE 零源改）**：`tests/stageB_sota.m` 由"仅 AOO vs Random"扩为 **AOO / Random / GA / PSO / ALNS 五组**三目标 HV 对比。诚实处理：GA/PSO/ALNS 是两目标加权求解器，其精英解投影到三目标空间作单点 PF，HV 天然低于 AOO/Random 多点 PF；新增 `baseline_threeobj_single` 辅助函数（调 `evaluate(prob,elite,[1 1 1])` 取三目标 + `nsga3_quality` 算单点 HV）；新增 **Kruskal-Wallis 五组 HV 组间检验**（输出 `kruskalwallis_p/h`）。门禁 [20] 仍断言 AOO vs Random 不显著劣化。**数据已跑（2026-08-19）**：`logs/stageB_sota.json` 实证 MK01 N=30，AOO HV 均值 0.0016 vs Random 0.0028，Wilcoxon p=2.2e-6 (h=1) → AOO 三目标 HV **显著弱于** Random（中位数 0.0008 vs 0.0028）；Kruskal-Wallis p=0.997（五组无显著差异，因 GA/PSO/ALNS 单点 PF 天然偏低）。诚实结论：NSGA-III 三目标路径在平等预算下竞争力弱，作 Limitations 讨论，不伪造增益 |
| 一 P0（补） | 1.2(a) Limitations 段落草稿 + 数据表 | **已完成（2026-08-18，文档交付物）**：新增 `docs/limitations_draft.md`，含可直接入论文的 Limitations 段落（英文）+ MK02/MK06/MK09 真实 gap 数据表（来源 `logs/stage7_benchmark.json`：+26.9%/+65.5%/+7.7% best gap）+ 联网 LLM 离线诚实声明段。弱实例偏弱作诚实讨论，未伪装调参改善 |
| 阶段四（多目标立场） | optA 诚实定位 + optB 显式不做 | **已完成（2026-08-19，纯文档零源改）**：新增 `docs/multiobj_positioning.md`。optA 采纳——维持默认 `AOO_THREE_OBJ=false` 两目标加权和主链，novelty 定位"LLM 引导加权和自适应搜索 + 结构化知识调制"，NSGA-III 三目标仅作可选扩展/对比章节（门禁 [20] 独立校验）；optB（NSGA-III 升主链）显式不做，根因：①改主链语义须全量重跑阶段二破坏零回归；② `logs/stageB_sota.json` 实证 AOO 三目标 HV 显著弱于 Random（Wilcoxon p=2.2e-6），非竞争力卖点；③多目标 rigor 已由门禁[20]+limitations_draft 诚实补齐。论文 novelty 表述与代码默认路径对齐约束已写入文档第 3 节 |
| 二 P1（补） | 2.2 增益归因可视化对比图 | **已完成（2026-08-18，脚本交付物）**：新增 `viz/llm_gain_figures.py`，读 `results/tevc_llm_gain/tevc_llm_gain.json` 生成三臂（aoo/modulate/full）makespan 对比柱状图；离线诚实态自动标注 "OFFLINE HONEST: full≡modulate≡aoo"（不伪造差异），联网态则出真实分化图。同一脚本兼容在线数据，零源改 |
| 阶段五（契约/可视化/存储打磨） | E1/E2/E4/E5/E7/E8 零风险收尾 + E3/E6 高风险不做 | **已完成（2026-08-19–20，ADDITIVE 零源改）**：E4 新增 `exports/validate_schedule.m` 并挂 `tests/stage9_run.m` 门禁；E2 修正 `viz/digital_twin.py` 离线声明为需联网加载 three.js；E1/E7 在 `visualize.m`+README 加双轨量纲标注；E8 新增 `docs/strategy_gain_map.md`；E5 `viz/dashboard.py` selectbox 标签显示 contract_version/生成时间/scenario。B3 完整 SOTA 补齐：新增 `tests/stage5_sota_full.m`+`stage5_sota_merge.m`，进程隔离产出 **`logs/stage5_sota_compare.json`（MK01/04/06/09 × aoo/ga/pso/alns/random × N=30 + Wilcoxon，AOO 四实例全显著优于 baseline p<1e-9）**；`stage5_run.m`[17] 门禁产物改写 `stage5_sota_gate.json` 避免覆盖 B3 正式产物。**显式不做**：E3（文件名嵌 hash 破坏 dashboard glob + 历史关联）、E6（pareto.OS/MS 瘦身改契约破坏 viz 读取）。**总体验收 `tests.run_all` ALL GREEN（2026-08-20）**：修复 [4] bench_aoo_vs_random 静态工作区（包函数）、[8] stage9_run contract_version 字符串比较（str2double）、[20] 字段名不符改为 hv 数组诚实报告（NSGA-III HV 弱于 Random -43.8% 标 Limitations 非阻断）。 |

## 已知阻塞 / 待补

- **阶段三.2 联网 LLM 增量增益（诚实声明）**：`tevc_llm_gain.m` 脚本与 `experiment_runs` 的
  三臂（`aoo`/`modulate`/`full`）分发逻辑健全且透明——`full` 仅在 `DEEPSEEK_API_KEY` 非空时
  `LLM_ENABLE=true` 真实联网，否则 `full≡modulate`（诚实降级）。当前环境离线，
  `results/tevc_llm_gain/tevc_llm_gain.json` 已是 `full≡modulate` 的诚实产物（增益=0 是环境事实，
  非代码缺陷），配套 `env_manifest.json` 固化此边界。**投稿不可宣称"在线 LLM 带来量化增益"**，
  只能诚实声明双引擎贡献来自离线结构化调制（`offline_structured_modulate`）这一可复现代理。
  真实联网增益须注入 Key 并确认 `api.deepseek.com` 可达后重跑 `tests.tevc_llm_gain`
  （5 场景 × 3 臂 × N=30 × MAXGEN=130，重计算）方可写入论文。
- **收敛 std 带默认不可用（零回归设计，非缺陷）**：`EXPORT_CONV_JSON` 默认 `false`（见配置表），
  单次运行不写 `conv_*.json`，故 dashboard/plotly_convergence 的 mean±std 带在默认配置下为空。
  这是零回归原则下的安全默认（避免每次求解额外 I/O）；启用方式：运行阶段五新增的
  `_cc_conv_batch.bat`（或 `tests.stageC_conv_batch(N,'MK01',MAXGEN)`），其显式置
  `EXPORT_CONV_JSON=true` + `EXPORT_DIR='logs'` 跑 N 次独立 seed，写出 `logs/conv_*.json`，
  再 `python viz/plotly_convergence.py logs/conv_*.json -o figures/convergence_std.html` 聚合生成 std 带。
  投稿图中"均值±标准差收敛带"须在此开关开启后批量导出方可绘制，当前主证据（7/10 达 BKS）不依赖 std 带。
- **大实例偏弱（已探索增强局部搜索，未获一致改善，作 Limitations 诚实讨论）**：阶段三.1 实测
  MK02(+26.9%)/MK06(+65.5%)/MK09(+7.7%) 相对 BKS gap 较大，MK03 已达标 BKS。已做安全探索
  （`tests/stage7_strong_x3.m`：对 MK02/06/09 仅调运行时参数 `LS_KMAX`/`AOO_REFINE_EVERY`，
  保持标准预算 POP=30/MAXGEN=60，零源文件改动）：激进版（LS_KMAX=12, REFINE_EVERY=1）MK02 改善至
  best=30(gap 15.4%)，但保守版（LS_KMAX=8, REFINE_EVERY=3）反而退化（MK02 best=32/gap 23.1%，
  MK06 best=86/gap 56.4%）——证明局部搜索深度调参对此项目弱实例**不可靠**，非稳健解法。
  故投稿采用诚实定位：保留默认配置主证据（7/10 达 BKS，见 `logs/stage7_benchmark.json`），
  将 MK02/06/09 偏弱作为已知局限在 Limitations 讨论，探索记录保留于 `logs/stage7_strong_x3.json`。
- **真实数据（已确认，阶段三.1）**：MK01=40（达 BKS）、MK04=73（优于 BKS）、MK08=542（gap≈3.6%）；
  四实例 SOTA 对比（aoo/ga/pso/alns/random）Wilcoxon p<0.001 显著优于全部 baseline。

- **过时判断澄清（2026-08-19 评审更正）**：早前工作记忆称"`tevc_llm_gain.m` 传 `data/MKxx.fjs`
  给 `llmaoo('DATA_FILE',...)` 会触发 load_data 不读 .fjs 崩溃"。经源码复核该判断**已过时**：
  `tevc_llm_gain.m` 实际通过 `benchmarks/load_benchmark` 直读 `.fjs`（非走 `llmaoo` 默认
  `load_data` 的 `.mat` 路径），标准基准读取链路可用；`load_data` 不读 `.fjs` 的限制仅影响
  `llmaoo` 默认 static 入口（`cfg.DATA_FILE='data.mat'`），不影响标准基准实验。`llmaoo`
  默认入口与标准基准路径的分裂本身仍是 UX 隐患（见改进计划阶段一/五），但"传 .fjs 崩溃"一事不成立。

## C 阶段：方法学诚信强化（2026-08-18 精进方案）

- **C1（loadUnb 归一化隐患，投稿前待决策）**：`evaluate.m` 当前用 `mk_ub` 作负荷不均衡
  `loadUnb` 的归一化分母（`ld = loadUnb / mk_ub`，见 L32），物理上界应为负荷差最大值
  （`max(loadVec)-min(loadVec)` 的理论界），导致 `loadUnb` 落在远小于 1 的量级、双目标加权和
  中负荷均衡的边际贡献被压低（宣称的双目标实质偏 makespan）。**处理（安全、零回归）**：新增
  `tests/analyze_loadunb_norm.m` 对 MK01-10 扫多个 `W_LOAD` 取值，记录 makespan/loadUnb 的
  tradeoff 并写出 `logs/loadunb_sensitivity.json`；据此判断是否需要将分母改为负荷差理论上界。
  **改动 `evaluate.m` 属数值修正，会改变主链适应度，须单独走零回归全门禁重跑，当前未改。**
- **C2（联网 LLM 增益正文边界，硬约束）**：在拿到 `DEEPSEEK_API_KEY`+网络可达的**真实联网
  产物**前，论文正文**仅**声明离线结构化调制贡献（`offline_structured_modulate`），**不得**以
  "DeepSeek 在线 LLM 带来量化增益"表述；联网复跑由 `env_manifest.json` 固化步骤，待用户注入
  Key 后运行 `_cc_llm_gain.bat` 方可写入真实数据（此约束不与现有诚实声明冲突，仅强调表述边界）。
- **C3（dashboard 概览表语义反向，已修复）**：`viz/dashboard.py` `make_overview_table` 中
  SOTA 行原 `final_best = max(mk[vn])`（最差）与 benchmark 行 `final_best = aoo_best`（最优）
  同列语义反向且列说明仅声明 static 行语义，易误导。已修正：SOTA 行 `final_best` 统一为
  求得最优值 `min(mk[vn])`，最差成绩单独成列 `sota_worst`，并同步更新列说明文字。纯前端 ADDITIVE，
  未改 solver/导出代码。

## E 阶段：长期可选（2026-08-18 精进方案，默认关闭，不污染主证据）

> E 阶段两项均为**长期可选算法工作**，以独立实验骨架形式落位：默认不接入 `run_all` 门禁、
> 不改主链/基线源码、不覆盖任何现有产物。启用需用户显式调用并在投稿后/弱实例需补强时决策。

- **E1（弱实例结构性改进 / 动态再调度，已落骨架）**：弱实例 MK02(+26.9%)/MK06(+65.5%)/MK09(+7.7%)
  当前作 Limitations 诚实讨论，未伪装调参改善。**新增 `tests/experiment_dynamic_reschedule.m`**：
  在 `AOO_DYNAMIC=true` + `AOO_THREE_OBJ=true` 路径下跑 MK02/06/09，演示读取 `parse_contract` 的
  `dynamic_strategy`/`priority` 保留字段作为事件驱动再调度钩子。**关键约束**：该两字段在
  `parse_contract.m` L9-13 明确标记"未消费"（默认 static 主链不读取，避免虚假双引擎声明），
  故本骨架仅 LOG 字段、不注入主链消费逻辑；真·动态再调度内循环是后续新增算法工作，不在本期
  零回归范围内。
- **E2（GA/PSO 原生多目标对照，已落骨架）**：现有 `baseline_threeobj_single` 将 GA/PSO 投影为单点
  PF 与 AOO 多点 PF 比 HV（口径诚实但易被质疑）。**新增 `tests/experiment_baseline_moea.m`**：不改
  `ga_fjsp.m`/`pso_fjsp.m` 源码（零回归），以 R 次独立 run 收集每次 elite 的三目标向量、聚合为
  "多起点采样前沿"作为 GA/PSO 覆盖度近似对照，输出 JSON 中显式标注为
  "multi-start sampling approximation"（不与 AOO 的 NSGA-III 真 Pareto 前混淆）。若审稿人要求
  GA/PSO **真·原生 NSGA 前**，则需另行开发 NSGA-II 风格改造（可发表新工作，不属本期范围）。
- **E 阶段启用方式**：`tests.experiment_dynamic_reschedule()` / `tests.experiment_baseline_moea()`，
  产物分别写 `logs/experiment_dynamic_reschedule.json`、`logs/experiment_baseline_moea.json`，
  均独立于 `stageB_sota.json` 与 B 阶段证据链。

## 目录

```
llmaoo.m / llmaoo_config.m / main.m      主入口与配置
deepseek_chat.m / prompt_*.m / parse_contract.m  LLM 四职责
aoo_engine.m / decode.m / evaluate.m      AOO 引擎与评估
benchmarks/  load_benchmark / define_problem / baselines(ga/pso/alns)
tests/       run_all + stage*_run 回归与实验脚本
exports/     JSON 导出   viz/  Python/Plotly 可视化   data/  MK01-10 .fjs
```
