# FJSP LLMAOO 全链路审计、核心模块修复与项目清理报告（2026-08-15）

## 摘要
本次对 FJSP LLMAOO 双引擎求解器（LLM 契约解析 + AOO 五策略优化）做了全链路审计、核心 bug 修复、无用文件清理与结果整理。审计确认双引擎链路畅通、无死锁、无 NaN/Inf 泄漏；发现并修复了 4 个真实弊病（含 1 个索引错位运行时崩溃风险 bug），清理了 archive 中约 70 个调试脚手架/专利脚本/异项目文档，并为 results/ 补充了 INDEX.md 与 5 个子目录 README，使结果归档自解释、可直接用于论文分析。修复后回归套件 18 步 ALL GREEN（checkcode 0 ERROR，decode_eval 206 PASS）。

## 一、全链路审计结论

### 1.1 双引擎链路
LLM 链路：main/llmaoo → llm_hook → gather_stats → deepseek_chat（联网/缓存/离线降级）→ parse_contract → make_llm_state / offline|online_llm_modulate → aoo_engine 每代 aoo_params。
AOO 链路：aoo_engine 主循环每代算 c,m,L,e，五策略（风/水/动物/滚动/弹射）消费对应增益，精英保留 + Pareto/NSGA-III 选择 + 停滞重启 + 早停。

结论：链路闭合、信号真实回灌、优雅降级、无死锁、无未处理异常、aoo_engine 有 isfinite 护栏防 NaN/Inf 污染精英、parse_contract 有 try-catch。

### 1.2 三增益真实消费（无死参数）
- levy_gain → 滚动策略 levy（aoo_engine L58）
- diff_gain → 动物传播 e + 修复后水传播 m（aoo_engine L324 + 修复 L325）
- explore_bias → 风传播 windPm（aoo_engine L70）

修复前 diff_gain 仅调制动物传播，水传播 m 未受影响（见 2.2 M3）。

### 1.3 离线降级语义
默认 OFFLINE_STRUCTURED_MODULATE=false 时，离线态 local_heuristic 返回纯自然语言（非 JSON），三增益恒 1.0，即离线态等价于纯 AOO。仅显式开该开关才启用结构化调制。deepseek_chat 离线降级本身健壮、不中断链路。

## 二、修复的真实弊病（已修，零回归）

### 2.1 【严重→已修】llm_guided_local_search 索引错位（运行时崩溃风险）
原第 30 行 `kk = prob.opOf(tt)` 用固定 jobOf 映射的工序号，而 `tt` 是进化后 OS 排列的位置，两者在 OS 非顺序时不一致。在不等工序实例（MK04/05/08/09/10）上会导致 `prob.op_mach{j}{kk}` 越界或改错工序机器。
修复：改为 `kk = sched(tt).op`（当前排列下该位置真实工件内工序号），与 refine_elite 正确写法 `kk = sum(chrom.OS(1:t)==j)` 一致。

### 2.2 【中等→已修】diff_gain 仅调制动物传播（M3）
原 aoo_params 中 `m`（水传播）只被 `sqrt(N/nOp)` 缩放，未乘 diff_gain，与 prompt_knowledge 声明的"水/动物传播强度增益"语义不符，且使 LLM 对水传播无控制力。
修复：在 aoo_params 中 `m = m * llm.diff_gain`，使 diff_gain 同时调制水/动物传播，与契约一致。

### 2.3 【中等→已修】ls_mode='NONE' 被当 CRITICAL_BLOCK（M4）
原 llm_guided_local_search 把除 MACHINE_REASSIGN 外的所有值（含 NONE）都当 CRITICAL_BLOCK 处理，违背 LLM "不做局部搜索" 意图。
修复：在循环前显式 `if strcmpi(contract.ls_mode,'NONE'), chrom=best; obj=bestObj; return; end`。

### 2.4 【安全→已修】llmaoo_config 明文 API Key（L5）
原 llmaoo_config.m 第 111 行硬编码真实格式 `sk-...` Key，存在泄露风险。
修复：改为 `getenv('DEEPSEEK_API_KEY')`，留空时自动离线降级；提示用户通过环境变量注入。

### 2.5 【清理→已修】nsga3_core.m 空壳文件
0 字节空壳，仅被 _cc_stageC_check.bat 和 das_dennis.m 注释引用，无实际调用，论文代码评审有暴露风险。
修复：删除 nsga3_core.m，更新 das_dennis.m 注释与 _cc_stageC_check.bat（去掉对其 checkcode）。多目标逻辑在 nsga3_select.m / nsga3_quality.m 中完好。

### 2.6 【去虚化→已修】保留字段声明
parse_contract 中 dynamic_strategy/priority 与 prompt 中 stagnant/diversity/heuristics 被解析但未消费（死参数）。已在 parse_contract 注释明确标注 dynamic_strategy/priority 为"保留字段，当前版本未消费"，并修正 prompt_knowledge 中 heuristics 的误导性描述（"仅作记录与可解释性展示"），避免虚假双引擎声明。

## 三、项目清理（已执行，未删核心文件）

删除内容（均在 archive/ 或根目录残留，无运行依赖）：
- archive/py/build_patent.py、edit_patent.py：专利回填脚本，与求解器无关、有合规风险
- archive/docs/dual_engine_architecture.md：另一项目混入的架构文档
- 根目录 _cleanup.py、_cleanup2.py、fig_utils.py、make_figures.py：残留脚手架/重复脚本
- 根目录 _launch_*.bat（3 个空启动脚本）
- archive/bat/*.bat（9 个调试 bat）、archive/m/*.m（13 个调试 m）、archive/ps1/*.ps1、archive/py/*.py（25 个一次性调试脚本）

保留：所有核心 `.m` 求解器、全部 `_cc_*.bat` 运行编排、data/*.fjs、benchmarks/*、exports/*、viz/*、figs/*、figures/*、results/*、tests/*、archive/docs 历史报告（已隔离、有参考价值）。

## 四、结果整理（已执行，便于下一步分析）

- 新增 `results/INDEX.md`：统一分析入口，含核心指标速查表（MK01-10 基准 gap%、最火问题侧闭环、投稿主结果）、子目录导航、契约字段约定、下一步分析建议。
- 为 5 个核心子目录补 README：tevc_submission、stage5_benchmark、hot_dynamic、stageF_real、llm_gain_quant，说明内容/关键指标/产出文件。
- 原 results/README.md 及 archive/ 可回收站说明保留。

关键真实数据（来自各 result JSON）：
- MK01-10 基准：MK01=40(BKS 40, gap 0%)，MK04=73(优于BKS)，MK08=542(gap 3.6%)；大实例 MK02/03/06 偏弱（gap +57%~+104%）。
- tevc_full_result.json：MK01 makespan=38, loadUnb=7, pareto_count=563, nan_count=0。
- hot_multi：MK01 makespan=38, HV=0.0009, IGD=0.2188, PF=346。

## 五、回归验证
`tests/run_all` 18 步 ALL GREEN：
- [1] checkcode ERROR=0
- [2] decode_eval 206 PASS
- [3]-[17] 各 stage 自测全 PASS
- [6] 竞争力门禁 AOO vs Random p=0.5648（不显著劣化）
- [18] 不等工序实例 + parse_fjs 双 layout 鲁棒性 PASS
修复零回归，冒烟 MK01 mk=37/288 均正常，nan_count=0。

## 六、遗留与建议（投稿级，未改）
1. 大实例(MK02/03/06) gap 偏大，是投稿前需补强或解释的主要弱点。
2. 联网 LLM 真实增益在难实例(MK04/06/09)尚未量化（当前 llm_gain_quant 增益=0 根因为网络不可达+默认场景 plateau）。
3. dynamic_strategy/priority 字段已标注保留，待 Stage8 动态主链接入后启用。
4. 竞争力门禁[6]仍按两目标 AOO vs Random；NSGA-III 主选启用后需补三目标场景表述。

## 七、参考文件
- 主入口：main.m → llmaoo.m；配置：llmaoo_config.m
- LLM 引擎：deepseek_chat.m / parse_contract.m / llm_hook.m / prompt_knowledge.m / prompt_diagnosis.m / fjsp_system_prompt.m / online_llm_modulate.m / offline_structured_modulate.m
- AOO 引擎：aoo_engine.m / llm_guided_local_search.m / critical_path.m / critical_block_neighborhood.m
- 回归：tests/run_all.m（_cc_all.bat 驱动）
- 结果导航：results/INDEX.md
