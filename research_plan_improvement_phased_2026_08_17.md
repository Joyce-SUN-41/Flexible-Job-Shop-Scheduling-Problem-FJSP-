# FJSP-LLMAOO 阶段性改进方案（v2 — 代码收口后到可投稿的最后一公里）

> 依据：2026-08-17 全项目评审（`research_report_project_review_2026_08_17.md`）+ 2026-08-17 工作日志。
> 关键前提（已核实）：阶段一~四**代码层已全部收口**，`tests/run_all.m` [1]–[18] **ALL GREEN**，
> `evaluate.m` 的 energy 塌缩根因（旧 `1.5*energy+1` 兜底）已修复（现优先固定界 `prob.e_ub`），
> `aoo_engine.m` NSGA-III 主选已传 `[1 1 1]` 真实三目标，`export_result_json.m` 已写 `contract_version='1.1'`。
> 当前**唯一阻塞投稿交付的缺口是"成果导出物"仍是 2026-08-16 旧版本，且未用修复后代码重跑**。
> 本方案聚焦"把已修复的代码转化为可投稿的真实交付物 + 残余弱点的诚实处理"，不重复造轮子。

---

## 阶段〇：重导出投稿主结果（P0，半天，阻塞项）

**问题**：`results/tevc_submission/tevc_full_result.json`（及 `tevc_multi_result.json`）生成于 2026-08-16 01:01，
早于全部修复：`version:"1.0"`（缺 `contract_version`）、`has_dynamic:true` 与 `has_energy:true` 同真但静态求解未走动态主链（标志位语义脱节）、`obj3` 第三维（energy）全文件 1873+ 处恒 `0.664495114`（旧 `1.5*energy+1` 兜底产物）。
论文插图若来自此文件，则与代码/正文语义脱节。

### 0.1 重导出全部 tevc_submission JSON
- 脚本：定位 `submit_tevc` / `tevc_full_result` 生成入口（memory 记 `tevc_full_result makespan=38, pareto_count=563`，但落盘 JSON 实为 mk=34，需核对入口与 `results/tevc_submission` 生成路径）。
- 验证：重导出后 `tevc_full_result.json` 顶层须含 `contract_version:"1.1"`；`obj3` 第三维方差 > 0（不再恒 0.6645）；`has_dynamic` 与 `has_energy` 语义须对齐（full 场景才双 true，static/multi 不得误标 dynamic）。
- 注意：`tevc_submission` 是否为联网 `full` 场景产物？若是，离线态 `full≡modulate`（见阶段三.2 诚实固化），须按 `env_manifest.json` 声明离线态，不得宣称在线 LLM 增益。

### 0.2 刷新论文插图来源
- `figures/` 下由旧 JSON 生成的 gantt/convergence/pareto HTML 与 `results/tevc_submission` 强关联者，须用新导出 JSON 重生成（`viz/plotly_gantt.py` / `plotly_convergence.py` / dashboard Pareto Tab）。
- 交付物：`tevc_submission` 全部 JSON 为真实刻度 + `contract_version:'1.1'` + energy 真实分化；插图与正文一致。

---

## 阶段一：多目标立场最终固化（P1，半天，文档+轻量代码）

代码已选"选项 A"：主链=LLM 引导两目标加权和自适应搜索，NSGA-III 作附加质量评估（默认关），energy 由 `W_ENERGY` 真实化。

### 1.1 确认 NSGA-III 仅作"附加评估"的论文表述
- `evaluate_population.m` 已正确：三目标时 `w=[W_MAKESPAN,W_LOAD,W_ENERGY]`，但返回的 `Z` 仍是 N×2（精英排序两目标加权和），energy 仅进 `extra.obj`。即 NSGA-III 的 `objAll` 用真实三目标（[1 1 1] 触发），但主链精英选择仍两目标——这是合规的"诚实定位"，须在论文/README 明示。
- 若审稿要求更强 rigor，再切"选项 B"（开 `AOO_THREE_OBJ` 默认）——代码分支已就绪，但会增加主链数值变化与门禁复跑成本，临近 deadline 不建议。

### 1.2 门禁 [6] 三目标表述补全
- `gate_competitiveness.m` 增加 `AOO_THREE_OBJ=true` 分支：用 HV/IGD（非加权和）比较 NSGA-III 主选 vs Random 的非支配前沿，使"附加多目标评估"有竞争力证据，且不污染主链加权和门禁。
- 验证：`tests/run_all.m` [10]（quality_metrics）检查 `pareto.energy` 非恒定 + HV 有界。

---

## 阶段二：联网 LLM 增益量化（P1，依赖外部，可并行尝试）

### 2.1 联网复跑（若存在 Key+网络）
- 前提：设置 `DEEPSEEK_API_KEY` 环境变量，`LLM_ENABLE` 自动 true。
- 脚本：`tests.tevc_llm_gain`（三臂 aoo/modulate/full + MK04/06/09 + dynamic + multi + Wilcoxon）。
- 若成功：用 `results/tevc_llm_gain/env_manifest.json` 标记在线态，将真实三臂增益写入论文 novelty 段。

### 2.2 联网不可达的诚实兜底（当前实际状态）
- 已固化：离线态 `full≡modulate`，`env_manifest.json` 明确"不可宣称在线 LLM 增益"。
- 论文 novelty 主张降级为"结构化 LLM 调制（离线契约解析 + 自适应增益注入）"，**不得**出现"online LLM improves X%" 等未验证表述。
- 交付物：novelty 段措辞与 `env_manifest` 状态严格一致。

---

## 阶段三：大/难实例补强或诚实讨论（P1/P2，1–2 天）

### 3.1 现状（已量化）
- `logs/stage7_benchmark.json`：7/10 达/超 BKS；MK02(+26.9%)/MK06(+65.5%)/MK09(+7.7%) 偏弱。
- `logs/stage7_sota.json`：MK01/04/06/09 × aoo/ga/pso/alns/random，AOO 全部 p<0.001 显著占优（含 MK06 虽绝对 gap 大但相对 baseline 仍优）。

### 3.2 处理策略（二选一，建议并行）
- **策略 X（补强）**：对 MK02/06/09 增加局部搜索（复用 `llm_guided_local_search` / `critical_block_neighborhood`）或延长 `AOO_MAXGEN`，重跑 `stage7_run` 刷新 benchmark JSON，缩小绝对 gap。
- **策略 Y（诚实讨论）**：在论文"Limitations"段如实说明大/难实例（工序数多、机器候选多）相对 BKS 偏弱，但相对同预算基线仍统计显著占优——这是 FJSP 文献常见诚实写法，不阻塞投稿。
- 建议：先 Y 写 Limitations，若时间允许再 X 补强 MK06。

---

## 阶段四：清理与投稿自检（P2，半天）

### 4.1 死代码/占位清理
- 删除 0 字节空文件：`nsga3_core.m`、`diag_buildpareto.m`、`verify_viz_multi.m`、`figures/gantt__demo.html`、`replay__demo.html`、`convergence__demo.html`、`tevc_p0verify_result.json`(0B)。
- `obj_eval.m`/`obj_of.m` 旧评估入口若确认废弃，移入 `archive/`（勿删，保留溯源）。
- `parse_contract.m` 的 `dynamic_strategy`/`priority` 字段保留但注释"未消费"，或加显式断言跳过，避免审稿人误读为已实现能力。

### 4.2 字段命名一致性
- 统一 `loadUnb`/`lb`/`loadVec` 命名（建议 JSON 统一 `loadUnb`，Python 端映射一致），消除驼峰/缩写混用导致的解析隐患。

### 4.3 收敛 std 带可用性
- `EXPORT_CONV_JSON`（llmaoo_config 默认 false）导致默认导出无 `*_conv_*.json`，dashboard 收敛页 std 带为空。
- 要么在 `experiment_runs`（N 次独立 run）默认产出 conv 文件，要么 README 明确标注"std 带需开启 EXPORT_CONV_JSON 或手设 stageF/hot 实验"。避免审稿人/用户误以为方差分析不可用。

### 4.4 投稿包自检清单
- [ ] `tevc_submission` 全部 JSON = 真实刻度 + `contract_version:'1.1'` + energy 非恒定（阶段〇）
- [ ] 多目标立场声明与图表一致（阶段一）
- [ ] LLM 增益措辞与 `env_manifest` 在线/离线态一致（阶段二）
- [ ] MK02/06/09 处理策略（补强或 Limitations 诚实讨论）落位（阶段三）
- [ ] 死代码清理 + 字段命名统一 + std 带说明（阶段四）
- [ ] `tests/run_all.m` [1]–[18] 全绿 + NaN/Inf=0

---

## 执行顺序与里程碑

| 优先级 | 阶段 | 风险 | 收益 | 前置 |
|---|---|---|---|---|
| **P0** | 阶段〇（重导出 tevc_submission） | 低（代码已就绪，仅重跑） | 高（消除旧归一化/旧兜底，投稿硬门槛） | 无 |
| P1 | 阶段一（多目标立场固化 + 门禁[6]三目标） | 低 | 高（novelty 合规） | 阶段〇 |
| P1 | 阶段二（联网 LLM 增益或诚实兜底） | 中（依赖 Key/网络） | 高（novelty 证据） | DEEPSEEK_API_KEY |
| P1 | 阶段三（大实例补强 / Limitations） | 低 | 中（竞争力诚实） | 阶段〇数据 |
| P2 | 阶段四（清理 + 自检） | 低 | 高（投稿安全网） | 阶段〇–三 |

**建议顺序**：阶段〇（立即，P0 阻塞项）→ 阶段二（并行尝试联网，可后台）→ 阶段一 → 阶段三 → 阶段四。

## 与旧 roadmap（research_plan_improvement_roadmap_2026.md）的关系
旧 roadmap 的阶段一~四（代码层契约清理、多目标修复、证据链长跑、收口）**均已落地且 run_all 全绿**，本 v2 方案不再重复这些代码改动，仅承接其"成果导出物未刷新"的最后一公里缺口（阶段〇）与残余弱点诚实处理（阶段一~四）。两者互补，不冲突。

## 关键约束
- 所有重导出须用**当前修复后代码**，禁止沿用 2026-08-16 旧文件。
- 联网增益若环境不可达，**不伪造数据**，严格按 `env_manifest` 诚实声明。
- 实验长跑用独立日志文件名（避免残留 matlab.exe 占用，参见 MATLAB 运行坑）。
- 不要重写大文件；用 `replace_in_file` 定点修改。
