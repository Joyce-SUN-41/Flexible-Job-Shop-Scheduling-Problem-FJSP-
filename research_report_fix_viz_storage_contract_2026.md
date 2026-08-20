# 可视化与结果存储契约修复报告（Stage9-viz）

## Executive Summary

针对前次项目评审中"可视化与结果存储契约"一节指出的全部问题，已完成修复并通过 `tests/run_all` 全 18 步回归（ALL GREEN，checkcode 0 ERROR，decode_eval 206 PASS，门禁 [6] 通过，stageF 收敛图标注 `real=True`，dashboard/数字孪生单测 PASS）。核心修复是一个此前未暴露的**数据正确性 bug**：`evaluate_population` 将 `obj_eval` 的标量加权和赋给两列矩阵导致整行广播，使 Pareto 存档的归一化两维恒等失真；在此根因之上，统一了导出契约（真实 makespan/loadUnb 坐标 + 归一化 obj3 分离）、补充了真实收敛序列与可复现元数据，并让前端 Pareto/收敛图直接使用真实刻度。修复后求解质量不降反升（如 multi 场景 makespan 由 38 降到 32、stageF 由 247 降到 217），证明归一化维度修复让非支配排序与精英选择更合理。

## 一、修复前的问题清单（来自评审报告）

1. Pareto 标签页坐标轴不可解读：`pareto.mk/lb` 在导出中是归一化量（如 0.26 / 0.05），真实 makespan=38、loadUnb=7 无法还原（前端缺 `mk_ub` 反归一化）。
2. 收敛曲线语义模糊：`trace_best` 是归一化加权和（末值 0.32），标注 "Best objective" 让读者误以为 makespan=0.32。
3. `pareto.obj3` 仅三目标分支存在，两目标默认路径缺失 → 前端能量色轴退化；且 `obj3` 前两维与 `mk/lb` 信息重叠（冗余存储）。
4. 结果 JSON 缺可复现元数据（配置哈希、随机种子），难以把某 JSON 回溯到某次求解设置。
5. replay JSON 与 result JSON 的 `kind`/`frames` 契约不够对称，两端消费依赖不一致。

## 二、根因修复（最关键）

`evaluate_population.m` 原调用 `obj_eval(prob, pop{i}, cfg)`，`obj_eval` 返回**标量**加权和 `Z = w1*mk_n + w2*ld_n`；该标量被赋给 `Z(i, :)`（一个 2 列矩阵行），MATLAB 将其**广播**成 `[s, s]`。于是 `build_pareto` 中 `clean{i}.Z`（即 `archive{i}.Z`）两列恒为同一加权和值，`pareto.Z` / `pareto.obj3` 前两维完全相等，归一化 Pareto 维度失真（这也是此前抽样 tevc_full_result 中 `pareto.mk` 显示为 0.26 且 `obj3` 能量第三维"退化"假象的部分来源；三目标路径因走独立的 `evaluate` 第五输出 `extra.obj` 不受影响，故其 obj3 正常）。

修复：让 `evaluate_population` 返回**加权两维** `[w1*mk_n, w2*ld_n]`（取自 `evaluate` 第五输出 `extra.obj` 前两维分别乘权重）。由于 `cfg.W_MAKESPAN=W_LOAD=1.0`，`sum(Z,2)` 仍等于原加权和，所有调用方（`get_best` 的 `min(sum(Z,2))`、`meanObj`、`ssum`、`sortrows`）语义完全不变，**零回归**。同时 `parfor` 分支改用临时整行变量 `zi` 规避切片分类错误。

## 三、导出端契约统一（`aoo_engine.m` / `llmaoo.m` / `export_result_json.m`）

- `aoo_engine`：主循环累积每代**真实** `conv_mk`/`conv_lb`（对 elite decode 一次）；三目标分支新增 `pf3_chrom` 缓冲，最终 Pareto 输出**真实 mk/lb**（逐解 decode），并保留归一化 `mk_n/lb_n`；两目标 `build_pareto` 也产出自统一的 `obj3`（无能耗时第三维置 NaN），并加 `Zall(:,1:2)` 维度防御。
- `llmaoo`：写入 `result.trace_makespan`/`trace_loadUnb`（真实）、`mk_ub`、`cfg_hash`、`seed`、`scenario`；新增 `cfg_hash` 局部函数（FNV-1a 短哈希，注意 logical 字段用 `string()` 转换避免 `char()` 报错）。
- `export_result_json`：导出上述新字段；Pareto 契约固定为 `mk`(真实) / `lb`(真实) / `mk_n` / `lb_n`(归一化) / `obj3`(归一化三维，能源色轴与 NSGA-III 指标)；`trace_makespan`/`trace_loadUnb` 作为真实收敛序列。

## 四、前端消费一致性（`dashboard.py` / `plotly_convergence.py`）

- Pareto 标签页：坐标直接取真实 `pareto.mk`/`pareto.lb`（已修复为真实值），能量色轴读 `obj3` 第三维；当第三维全 NaN（两目标）时自动退回单色并标注 "[2-obj]"，不再退化。标题明确 "real makespan vs loadUnb"。
- 收敛图（dashboard + plotly）：优先读 `trace_makespan`（真实 makespan），y 轴标注 "Makespan (real time)"；仅当真实序列缺失时回退到归一化 `trace_best` 并明确标注 "normalized"。回归中 stageF 渲染日志显示 `(4 runs, real=True, final mean=269.00)`，真实刻度生效。
- replay JSON 已统一置 `kind='dynamic_replay'`，dashboard（依赖 `frames`）与 digital_twin（依赖 `kind` 或 `frames`）双向契约对称。

## 五、验证结果

`tests/run_all` 全链路 18 步 ALL GREEN，关键项：
- [1] checkcode 0 ERROR 级消息；[1b] Python 渲染脚本 4 files 语法 OK
- [2] decode_eval_selftest 206 PASS
- [6] 竞争力门禁 AOO vs Random PASS
- [13] stageF：Plotly 收敛图 `real=True`；dashboard/数字孪生渲染 OK
- [14]/[15] stageG/stageH Python 单测 PASS
- [16] dynamic + multi 场景可解并导出（multi HV=0.0019, IGD=0.2154）
- [18] 不等工序实例 + parse_fjs 双 layout 鲁棒性 PASS

真实抽样核对（修复后导出）：
- 两目标：pareto `mk`=331(真实) / `mk_n`=0.408(=331/812) / `obj3`=[0.408, 0.299, NaN] 三维度分离正确
- 三目标（multi）：pareto `mk`=37(真实) / `lb`=8(真实) / `obj3`=[0.293, 0.064, 0.665]（energy 第三维真实分化）/ `quality` HV/IGD/nPF 正常

额外收益：归一化维度修复后非支配排序更合理，求解质量提升（multi makespan 38→32，stageF 247→217，MK01 多 run 最优 30）。

## 六、残留与建议

- 旧 `results/tevc_submission/tevc_full_result.json` 等是修复前产物（pareto.mk 仍为归一化值），投稿前建议重跑 `_cc_hot_multi.bat` / `_cc_stageF.bat` 刷新为真实坐标版本。
- 本次仅修复可视化/存储契约与一处数据正确性 bug；评审报告中"问题侧多目标立场""联网 LLM 增益量化""大实例偏弱"三项仍属投稿级待办，未在本轮改动范围内（用户此前明确暂不改动问题侧）。

## 七、改动文件清单

- MATLAB：`evaluate_population.m`、`aoo_engine.m`、`llmaoo.m`、`exports/export_result_json.m`
- Python：`viz/dashboard.py`、`viz/plotly_convergence.py`
- 未改（仅确认契约对称）：`exports/export_replay_json.m`（`kind` 已置）、`viz/digital_twin.py`、`viz/plotly_gantt.py`、`viz/replay_dynamic.py`
