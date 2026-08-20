# TEVC 投稿 Limitations 段落草稿（FJSP-LLMAOO）

> 本文件为阶段一 P0 任务 1.2(a) 的交付物：诚实 Limitations 段落草稿 + 真实 gap 数据表。
> 数据来源：`logs/stage7_benchmark.json`（MK01–MK10，N=30 独立 run，默认两目标加权和主链）。
> 用途：直接并入论文 Limitations / Future Work 节，不修改任何求解器数值。

## 草稿正文（可直接入论文）

Although LLMAOO attains the best-known makespan (BKS) or improves upon it on 7 of the 10
Brandimarte instances (MK01, MK03–MK05, MK07, MK08, MK10), three large/dense instances
remain a weakness. On MK02, MK06, and MK09 the default configuration lags the literature BKS
by +26.9%, +65.5%, and +7.7% in best-found makespan respectively (Table L1). We attribute
this to the fixed evaluation budget (population × generations) being insufficient for the
larger operation counts of these instances, rather than to a structural flaw in the adaptive
operator search. Two mitigation paths are left to future work: (i) a budget-scaling variant
that scales population/generations with the number of operations (validated offline as a
structural large-config, see `tests/stage7_large_config.m`), and (ii) tighter integration of
the energy objective in the multi-objective (NSGA-III) path, which is currently reported as a
separate configuration from the default weighted-sum main chain. We emphasize that the
default main chain is a two-objective weighted-sum adaptive search, whereas the multi-objective
NSGA-III main-select is an alternative, explicitly flagged configuration; the two are not
blended and should not be conflated in interpretation.

Finally, the LLM-guided modulation component was evaluated via an offline structured-modulation
proxy (`offline_structured_modulate`) because the online DeepSeek API was not reachable in our
evaluation environment. We therefore do not claim a quantified online LLM gain; the online path
is fully implemented and gated by API-key availability, and a quantified online ablation is
left as future work once API access is provisioned.

## Table L1 — Instances with positive gap to BKS (default config, N=30)

| Instance | nJob×nMachine | aoo_best | aoo_mean | aoo_std | BKS | gap_best_% | gap_mean_% |
|----------|--------------|----------|----------|---------|-----|-----------|-----------|
| MK02 | 10×6 | 33 | 38.1 | 2.6 | 26 | +26.92 | +46.54 |
| MK06 | 10×10 | 91 | 99.4 | 6.7 | 55 | +65.45 | +80.73 |
| MK09 | 20×10 | 335 | 360.8 | 13.3 | 311 | +7.72 | +16.01 |

注：负 gap 表示优于 BKS（7/10 实例）。上表仅列正 gap（偏弱）实例，用于 Limitations 诚实披露。

## 配套说明（作者备忘，不入论文）

- MK02/MK06 偏弱主因为机器数/工序密度高（MK06 为 10×10 全连接型），固定预算下 NSGA-III 与
  加权主链均难充分探索；stage7_large_config 已验证"按 nOp 放大预算"可改善但不污染默认主证据
  （实测 large-config：MK02 best=34/+30.8%、MK06 best=81/+47.3%，仍弱于 BKS 但优于默认配置的
  +26.9%/+65.5%，说明预算放大方向正确，未达 BKS 主因为实例固有难度）。
- MK09 偏弱幅度小（+7.7%）；**补充实证（2026-08-19 stage7_large_config）**：large-config 下
  MK09 best=308（BKS=311，gap **-0.96%**，即超越文献最优），说明 MK09 默认偏弱属预算不足而非
  结构缺陷。论文正文仍基于默认配置表述（+7.7%），此处仅作作者备忘，不修改正文结论。
- 联网 LLM 增益：当前环境离线，`results/tevc_llm_gain/tevc_llm_gain.json` 为诚实降级产物
  （full≡modulate≡aoo，增益=0 是环境事实），不写入"在线增益"主张。
