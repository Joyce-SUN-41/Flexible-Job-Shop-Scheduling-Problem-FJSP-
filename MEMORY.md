# 长期记忆 (MEMORY.md)

## 项目：FJSP 柔性作业车间调度求解器 (MATLAB, LLMAOO 双引擎)
- 路径：`c:\Users\Joyce_SUN\Desktop\FJSP`
- 当前阶段状态（2026-08-12）：阶段1-9 + A + B 已全部落地并 `tests/run_all` ALL GREEN。
  - 阶段A：动态多目标默认场景一键激活（`llmaoo('AOO_DEFAULT_SCENARIO','multi'/'dynamic')`，默认 `'static'` 零回归）。
  - 阶段B：NSGA-III 参考点关联 + HV/IGD 标准指标（附加层，`res.quality.HV/IGD`，主搜索仍两目标加权和）。
- 待做：阶段C（填 DEEPSEEK_API_KEY + 开 OFFLINE_STRUCTURED_MODULATE 量化 LLM 增益，最关键、翻转正增益唯一抓手）；阶段D（完整 MK01-10 N=30 + SOTA 对比）；可视化阶段E（装 plotly 渲染阶段9三件套）。
- 目标期刊：IEEE TEVC；要求 novelty / 标准基准对比 / 统计显著性 / 多目标严谨(HV/IGD)。
- 用户中文交流，回答用简体中文。

## 关键字段约定（曾反复踩坑，务必一致）
- prob 新字段名（外部一律用）：`nJob / nMachine / nOpPerJob / op_mach{j}{k} / op_time{j}{k} / machW / mk_ub`。`load_data` 旧名 num_job/num_op 已内部映射。
- MS 存候选机器索引；能耗/解码须经 `prob.op_mach{j}{k}(mIdx)` 映射。
- `prob.AOO_THREE_OBJ`：多目标激活标志，define_problem('multi') 经 attach_energy 与 attach_stage8 均会置 true；build_pareto/quality 判断依赖它。
- `cfg.HV_REF`：NSGA-III 参考点，空=自适应（每目标 max*1.1）。

## MATLAB 实测坑（R2024b, Windows）
- matlab.exe 路径：`E:\Matlab R2024b\bin\matlab.exe`。
- 必须用 `.bat` + `cmd /c` 调 `-batch`（PowerShell 直接调有引号/& 冲突）；bat 内路径含空格需引号包裹。
- 验证脚本须纯 ASCII 文件名（中文/下划线前缀在 -batch 报"文本字符无效"；MATLAB 函数名不能以 `_` 开头）。
- `-batch` 下 `fprintf` 重定向文件会缓冲不 flush（日志空）→ 用 `diary('x.log')` 实时写盘；残留 matlab.exe 进程会占日志，需 `tasklist /fi "imagename eq matlab.exe"` 查、`taskkill /f /im matlab.exe` 清。
- `llmaoo` 键值对覆盖通过 `fieldnames(cfg)` 动态匹配，须用完整字段名（如 'AOO_MAXGEN' 非 'MAXGEN'）；'AOO_DEFAULT_SCENARIO' 走 cfg_stageA 同样机制。

## LLMAOO 主链结构（已定型）
- 入口 `llmaoo(cfg,...)` → `aoo_engine(prob,cfg,llm_state,hook)` 返回 `[elite, aoo]`；llmaoo 第100-114行显式重构 result（含 `result.pareto=aoo.pareto` 与 `result.quality=aoo.quality` 转发）。
- `aoo_engine` 输出 `aoo` 含 conv_best/conv_mean/pareto/quality；主搜索用两目标和（`sum(Z,2)`）。
- 双引擎：AOO 五策略离散邻域 + LLM 外部调制器（OFFLINE_STRUCTURED_MODULATE / DEEPSEEK_API_KEY 未填时离线降级）。
- decode 为 semi-active 解码（注释曾夸大）；AGV 约束需 `decode(prob,elite,cfg)` 第三参（nargin>=3 守卫）。
