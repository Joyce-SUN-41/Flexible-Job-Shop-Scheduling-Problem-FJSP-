#!/usr/bin/env python3
"""Stage9 visualization (batch 1): convergence curve with mean +/- std band.

Reads one or more results_*.json (N independent runs) and overlays:
  - each run's best trace (light)
  - mean +/- std band across runs
  - optional SOTA baseline trace (e.g. a JSON with only trace_best)

Usage:
    python viz/plotly_convergence.py results_*.json -o figures/convergence.html
    python viz/plotly_convergence.py run1.json run2.json ... -b baseline.json
"""
import argparse
import glob
import json
import sys

import numpy as np
import plotly.graph_objects as go


def load(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pattern", nargs="+", help="result json file(s) or glob")
    ap.add_argument("-o", "--out", default="figures/convergence.html")
    ap.add_argument("-b", "--baseline", default=None, help="optional SOTA baseline json")
    args = ap.parse_args()

    files = []
    for p in args.pattern:
        files.extend(glob.glob(p))
    if not files:
        print("[plotly_convergence] no input files matched", file=__import__("sys").stderr)
        return

    traces = []
    maxlen = 0
    real = False
    for f in files:
        d = load(f)
        tb = None
        if d.get("trace_makespan"):
            tb = np.array(d["trace_makespan"], dtype=float)
            real = True
        elif d.get("trace_best"):
            tb = np.array(d["trace_best"], dtype=float)
        if tb is None:
            continue
        maxlen = max(maxlen, len(tb))
        traces.append(tb)

    if not traces:
        print("[plotly_convergence] no trace_best/trace_makespan found", file=sys.stderr)
        return

    # pad and stack
    M = np.full((len(traces), maxlen), np.nan)
    for i, tb in enumerate(traces):
        M[i, : len(tb)] = tb

    mean = np.nanmean(M, axis=0)
    std = np.nanstd(M, axis=0)
    x = np.arange(1, maxlen + 1)

    fig = go.Figure()
    for i, tb in enumerate(traces):
        fig.add_trace(go.Scatter(
            x=np.arange(1, len(tb) + 1), y=tb, mode="lines",
            line=dict(width=0.8, color="rgba(76,120,168,0.35)"),
            name=f"run {i+1}", showlegend=False,
        ))
    fig.add_trace(go.Scatter(
        x=np.concatenate([x, x[::-1]]),
        y=np.concatenate([mean + std, (mean - std)[::-1]]),
        fill="toself", fillcolor="rgba(76,120,168,0.2)",
        line=dict(color="rgba(255,255,255,0)"), name="mean +/- std",
    ))
    fig.add_trace(go.Scatter(
        x=x, y=mean, mode="lines", line=dict(width=2.5, color="#E45756"),
        name="mean best",
    ))

    if args.baseline:
        b = load(args.baseline)
        tb = np.array(b["trace_best"], dtype=float)
        fig.add_trace(go.Scatter(
            x=np.arange(1, len(tb) + 1), y=tb, mode="lines",
            line=dict(width=2, dash="dash", color="#54A24B"),
            name="SOTA baseline",
        ))

    # D2 修正: 显式声明样本语义，避免把单次轨迹误读为 mean+/-std 带。
    # 仅当 N>=2 时 std 带才有意义；单文件输入时 std=0 带退化为中线，需明确标注。
    n_runs = len(files)
    if n_runs >= 2:
        subtitle = (f"Aggregated from {n_runs} INDEPENDENT runs (batch-exported). "
                    f"Band = mean ± std across runs; light lines = individual runs.")
    else:
        subtitle = ("Single run: mean±std band is degenerate (std=0). "
                    "For a real band, batch-export N>=2 independent runs via "
                    "tests.stageC_conv_batch and pass them together.")

    fig.update_layout(
        title="Convergence (best makespan, lower is better)" if real
        else "Convergence (best objective, lower is better)",
        # D2: 副标题声明独立 run 语义
        title_text=("Convergence (best makespan, lower is better)<br>"
                    "<sub>" + subtitle + "</sub>") if real
        else ("Convergence (best objective, lower is better)<br>"
              "<sub>" + subtitle + "</sub>"),
        xaxis_title="Generation",
        yaxis_title="Makespan (real time)" if real
        else "Best weighted objective (makespan + loadUnb)",
        template="plotly_white", height=520,
    )
    fig.write_html(args.out)
    print(f"[plotly_convergence] wrote {args.out} ({n_runs} runs, real={real}, final mean={mean[-1]:.2f})")


if __name__ == "__main__":
    main()
