# 研究计划：消除 LLMAOO 与 TEVC 投稿要求的所有差距（2026-08-14）

## 目标
用户明确要求"解决所有差距，可以联网跑真实 LLM 版"。三大差距：
1. 默认静态单目标设定非最火前沿（dynamic/multi/NSGA-III/green/AGV 已就绪但未激活）。
2. LLM 增益从未量化（之前在加权和单目标+plateau 框架增益=0）。
3. 完整 N=30 MK01-10 + GA/PSO/ALNS/NSGA-II 同预算 SOTA 对比未常态跑。

## 已核实事实（避免重复研究）
- `llmaoo_config.m` 默认值：AOO_DEFAULT_SCENARIO='static'、EXPORT_JSON=false、ONLINE_LLM_MODULATE=false；备用 DEEPSEEK_API_KEY 已填(L111)。
- `deepseek_chat.m` 用 webwrite 调 DeepSeek，'full' 变体在有 Key 时自动 LLM_ENABLE=true 联网，mode='online' 时 online_llm_modulate 保留真实增益。
- `experiment_runs.m` 已支持 Variants={'full','aoo','modulate','random','ga','pso','alns'}，'full' 变体联网。
- `tests/stage7_run.m` 已搭好 MK01-10 N=30 + 多实例(MK01/04/06/09) SOTA 框架，含 Wilcoxon。
- `tests/stat_report.m` 用 ranksum(Wilcoxon) + 95%CI + rank-biserial 效应量。
- `aoo_engine.m` L124-135：**NSGA-III 主选择已真正启用**（nsga3_select 调用，三目标模式），非仅指标层。L42 打印确认。
- `data/` 有 MK01-10 全部 .fjs。
- 之前联网 MK01 增益=0 根因：加权和单目标 + AOO 收敛到 plateau，LLM 调制无数值空间。

## 决策（基于用户明确指令）
- 差距1：采用"新增投稿级一键入口 submit_tevc.m + _cc_submit.bat 固化最火配置"为主，零回归保留 llmaoo_config 默认 static；但把 EXPORT_JSON 默认改为 true（可视化常态化，安全）。最火入口 = full 场景(dynamic+green+AGV) + multi 三目标 + 联网 LLM。
- 差距2：在难实例(MK04/06/09) + 动态/多目标场景跑联网 'full' 变体，让 LLM 在 AOO 未收敛/扰动场景显价值。预算：精选关键场景 N=30。
- 差距3：跑 stage7_run（MK01-10 N=30 基准 + 多实例 SOTA 含联网 full）。

## 执行步骤
1. 新建 `submit_tevc.m`：固化投稿最火配置（full 场景 + multi 三目标 NSGA-III + EXPORT_JSON + 联网 LLM），端到端求解+导出+渲染，产出 logs/tevc_*.json + figures/tevc_*.html。
2. 新建 `_cc_submit.bat`：matlab -batch 调 submit_tevc。
3. 写 `tevc_llm_gain.m`：在难实例 MK04/06/09 + dynamic/multi/full 场景跑联网 'full' vs 'aoo' vs 'modulate' 消融（N=30），量化 LLM 真实增益，产出 logs/tevc_llm_gain.json。
4. 跑 stage7_run（完整 SOTA，联网 full 变体）→ logs/stage7_benchmark.json + stage7_sota.json。
5. 验证 NSGA-III 主选择正确性（子代理）：确认 nsga3_select 在三目标模式真正替换两目标和选择，且 Pareto/quality 字段一致。
6. 验证可视化渲染闭环（子代理）：确认 tevc_*.json 能被 viz 五件套正确渲染。
7. 跑 tests/run_all 确认零回归（默认 static 仍 ALL GREEN）。
8. 汇总产出 TEVC 投稿级证据链报告 research_report_tevc_gap_closure.md。

## 信息检索策略
- 使用 wechat-article-search 技能检索 2026 最新 TEVC FJSP 投稿范式（NSGA-III 三目标、DFJSP 数字孪生、LLM4EO 在线算子元进化），确认 novelty 表述与对比基线设置是否对齐。
- 关键词："柔性作业车间调度 NSGA-III 多目标 2026"、"动态重调度 数字孪生 TEVC"、"LLM 进化优化 FJSP"，时间范围 2025-11 至 2026-08。
- 结合 web search 验证 DeepSeek API 当前可用性（备用 Key 是否仍有效）。

## 子代理分配
- 子代理A：验证 NSGA-III 主选择 + Pareto/quality 链路正确性（读 aoo_engine + nsga3_select + nsga3_quality + das_dennis）。
- 子代理B：验证可视化渲染闭环（读 export_result_json + viz 五件套 + 用 tevc demo json 试渲染）。
- 主代理：写 submit_tevc / tevc_llm_gain / _cc_submit，并实际跑实验、汇总报告。
