# 阶段性改进计划（投稿级收口路线图）

日期：2026-08-17
依据：`review_project_audit_2026-08-17.md`（同日审查报告）
目标期刊：IEEE TEVC
总原则：保持既有"零回归 / ADDITIVE"工程纪律——所有新开关默认关，旧数值语义不变；改动只补强证据与诚实定位，不重写主链。

---

## 阶段一（P0，低风险，1~2 天）：存储与可视化契约清理

目标：消除不可解读/误导性的展示与遗留旧数据，让投稿前拿到的所有产物都是真实、一致的。

1.1 重导出旧归一化投稿 JSON
- 用当前代码重跑 `submit_tevc.m` / `tevc_submission` 路径，覆盖 `results/tevc_submission/tevc_full_result.json`。
- 校验新 JSON：mk 为真实 makespan（非 0.264 归一化）、energy 维在开 `AOO_THREE_OBJ` 时真实分化（非恒 0.6645）、`has_dynamic` 与静态求解语义一致（不出现静态求解却 `has_dynamic=true` 的脱节）。

1.2 统一 Pareto 契约 `obj3` 语义（消除两分支不一致）
- 现状：`build_pareto` 两目标分支 `obj3=[Zsel,NaN]`（Zsel=归一化加权和分量），三目标分支 `obj3=[mk_n,ld_n,en_n]`——前两列含义不同。
- 改动：`build_pareto` 两目标分支改为 `obj3=[mk_n,ld_n]`（无 energy 维），与三目标分支前两列对齐；前端 `make_pareto_figure` 取 `obj3[:,2]` 作 energy 色轴在两目标时全 NaN 已正确处理，无需改前端。
- 风险：低，仅影响附加 obj3 字段结构。

1.3 概览表语义澄清（`viz/dashboard.py` `make_overview_table`）
- 现状：benchmark 行 `mks=r.get("aoo")`（求得值）而 `final_best=r.get("bks")`（理论最优），同表两列混义且无表头说明。
- 改动：新增显式列名（如 `aoo_makespan` / `bks`），或在 caption 注明"final_best=BKS"。避免读者误把 BKS 当成求得值。

1.4 收敛 ±std 带产出收口
- 现状：`export_result_json` 默认不产出 `*_conv_*.json`，导致仪表盘/plotly_convergence 的 std 带默认空，收敛图只有单条线，不利于"统计显著性"展示。
- 改动（二选一，推荐 a）：
  - a) 新增可选 `EXPORT_CONV_JSON`（默认 false，零回归），开启时随主结果写出独立 run 的 `trace_makespan` 序列文件，供 std 带聚合；在 README 文档化"多 run 方差需开此开关 + N 次独立 run"。
  - b) 仅文档化：明确告知 std 带依赖外部 stage7 长跑脚本产出，不纳入默认导出。
- 推荐 a，因投稿需随时复现方差证据。

1.5 旧格式 JSON 隔离
- `discover_results` 递归扫描 `logs/figures/results` 会把旧归一化 JSON 与新格式混显。新增：导出时写 `contract_version` 字段（当前 v1.0），前端/发现逻辑对 v<真实刻度版本的文件加"legacy"标注或跳过。
- 风险：低，纯展示层。

1.6 结果文件归集
- 时间戳文件名 `results_<timestamp>.json` 无覆盖/归集，目录堆积。新增 `EXPORT_DIR` 配置（默认 `results/`）并建议投稿跑统一命名（如 `tevc_submission`），避免历史文件污染概览表。

---

## 阶段二（P1，定位诚实性 + 多目标 rigor，2~4 天）：三目标与 LLM 增益

目标：把"伪三目标"变成可辩护的真实多目标，并把双引擎贡献从"恒等变换"变成"可量化证据"。

2.1 接入真实 energy 权重 `W_ENERGY`（修复第三维退化）
- 改动：
  - `llmaoo_config.m` 增 `cfg.W_ENERGY = 0`（默认 0，零回归；三目标场景置 1.0）。
  - `evaluate.m` 第 44-46 行 `w3 = 0` 改为 `w3 = cfg.W_ENERGY`（需把 cfg 传入 evaluate；当前 `evaluate(prob,chrom,w)` 的 w 由 `evaluate_population`/`obj_of` 用 `[W_MAKESPAN,W_LOAD]` 构造，需在此处拼入第三维 `w(3)=cfg.W_ENERGY`）。
  - `cfg_hash` 追加 `cfg.W_ENERGY`（防止不同 energy 配置哈希撞车，不可溯源）。
- 效果：开启后 energy 真正参与主链加权（诚实的加权和多目标）；NSGA-III 分支本就非支配，不受影响。

2.2 多目标 honest positioning（二选一，需定稿）
- 选项 A（低工作量、安全）：正文诚实定位为"LLM 引导的加权和自适应搜索，NSGA-III 作附加质量指标（HV/IGD）"。保持 `AOO_THREE_OBJ` 默认关，仅作分析。
- 选项 B（高工作量、强 rigor）：把 NSGA-III 主选择设为三目标模式的**默认主选**（`AOO_THREE_OBJ` 默认 true + `W_ENERGY` 默认非零），主链真正走非支配排序而非加权和。代码分支（`aoo_engine` L130-154）已就绪，需补：门禁 [6] 三目标表述、消融实验三目标版、stage7 长跑三目标复跑。
- 建议：若时间紧选 A 并强化 NSGA-III 指标作为"附加贡献证明"；若追求 TEVC 多目标 rigor 选 B。

2.3 联网 LLM 增益量化（双引擎贡献证据）
- 现状：默认离线 `full≡modulate`，增益为 0；`tevc_llm_gain.m` 三臂（aoo/modulate/full）+ MK04/06/09 + dynamic/multi + Wilcoxon 已备，但需 `DEEPSEEK_API_KEY`+网络。
- 改动：
  - 确认/补充环境变量注入：`cfg.DEEPSEEK_API_KEY = getenv('DEEPSEEK_API_KEY')`（已存在）；运行 `_cc_stageD_ablation.bat` 类脚本联网跑 `tevc_llm_gain`。
  - 若网络仍不可达：正文诚实声明"离线态双引擎协同以结构化调制呈现，在线增益受 API 限制未量化"，并把离线结构化调制（`OFFLINE_STRUCTURED_MODULATE=true`）作为可复现的替代证据。
  - 门禁补充：AOO vs Random 竞争力门禁 [6] 已有 p=0.5648（不显著劣化），需补 LLM 调制臂 vs 纯 AOO 的对比 p 值。

2.4 大/难实例补强或诚实讨论
- 现状：MK02(+26.9%)/MK06(+65.5%)/MK09(+7.7%) 偏弱。
- 改动（推荐先做诚实讨论，再做算法补强）：
  - 正文新增"局限性"小节，明确列出偏弱实例与 gap，作为未来工作。
  - 算法补强（可选）：对 elite 增加更频繁的 `refine_elite` 或增加 `AOO_POP`/`AOO_MAXGEN` 在难实例上的预算；验证 MK02/06/09 gap 是否下降。

---

## 阶段三（P0/P1，证据链长跑，后台运行）：基准与 SOTA 复跑

目标：用当前（阶段一/二修复后）代码刷新全部证据，确保投稿数字来自最新实现。

3.1 全基准重跑（MK01-10，N=30）
- 脚本：`tests/stage7_run.m`（`logs/stage7_benchmark.json`，标准 BKS 重算 gap）。
- 注意：上次 `logs/stage7_benchmark.json` 曾被旧进程清空后用 `viz/rebuild_benchmark.py` 还原；本次重跑前确认无残留 matlab 进程抢 CPU（用户曾两次拒绝 taskkill，需自然结束）。
- 产物：刷新 `stage7_benchmark.json`，附标准 BKS gap 表。

3.2 SOTA 对比复跑（aoo/ga/pso/alns/random，N=30，Wilcoxon）
- 脚本：`tests/stage7_sota_only.m`（`logs/stage7_sota.json`）。
- 已修复真 bug（2026-08-17）：`ga_fjsp`/`pso_fjsp` 的 `opOf` 误用越界、`signrank` 误取 h、预算硬编码覆盖——这些已落地，复跑应直接 pass。
- 产物：刷新 `stage7_sota.json`，附真实 Wilcoxon p 值。

3.3 多目标质量指标（若阶段二选 B）
- 三目标模式复跑，刷新 HV/IGD 证据（`result.quality`）。

3.4 联网 LLM 增益长跑（依赖阶段二.3 的 Key/网络）
- 后台跑 `tevc_llm_gain.m`，产出 `llm_gain_quant.json`。

---

## 阶段四（P2，收口，1 天）：门禁全绿 + 文档刷新

目标：投稿前最后一致性检查。

4.1 全门禁复跑
- `tests/run_all.m` [1]-[18] 全绿（当前已知全绿，改动后需复跑确认无回归）。
- 特别关注：阶段二改 `evaluate`/`cfg_hash` 后，门禁 [6] 竞争力、[2] decode_eval 206 PASS 不受影响。

4.2 cfg_hash 与 README 刷新
- `cfg_hash` 追加 `W_ENERGY`/`AOO_THREE_OBJ` 等可读开关（部分已含，补全）。
- `README.md` 配置字段表、JSON 契约、阶段状态、已知阻塞（含"联网增益未量化"诚实声明）刷新。

4.3 旧产物清理
- 删除/归档 `results/tevc_submission` 下旧归一化 JSON（已被 1.1 覆盖）；确认 `logs/figures` 无遗留旧格式混入 discover。

---

## 执行顺序与依赖

阶段一(P0) → 阶段三.1(P0 后台长跑，耗时 30-60min，可与阶段二并行) → 阶段二(P1) → 阶段三.2/3.3/3.4(P1，依赖阶段二定稿) → 阶段四(P2)。

关键里程碑：
- M1：存储/可视化无误导（阶段一完成）。
- M2：双引擎增益有量化证据 OR 诚实声明 + 三目标真实化（阶段二完成）。
- M3：全部证据来自最新代码（阶段三完成）。
- M4：门禁全绿、文档一致（阶段四完成）= 可投稿。

## 不需要改的部分（保持现状）
- AOO 五策略算子结构、零回归边界、ADDITIVE 工程原则。
- `decode.m` 半主动解码与 AGV/active 后处理（已正确）。
- 数字孪生 Three.js 主体（仅 Z 分层在大作业数下的重叠属展示瑕疵，非阻塞，可延后）。

## 风险评估
- 阶段二.1 改 `evaluate` 入参（注入 cfg.W_ENERGY）触及主链评估入口，需回归门禁 [2]/[6]；改动小但务必复跑。
- 阶段二.2 选 B 工作量较大（需三目标消融 + 门禁三目标表述 + 复跑），若临近 deadline 退回选 A。
- 阶段三长跑受 matlab 进程/CPU 竞争影响，需确保无残留进程。
