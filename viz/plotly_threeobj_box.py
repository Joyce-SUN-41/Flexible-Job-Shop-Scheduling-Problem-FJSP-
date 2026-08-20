#!/usr/bin/env python3
"""Stage3 P1 (D3): three-objective competitiveness box plot.

Reads logs/stageB_sota.json produced by tests.stageB_sota.m and renders a
self-contained HTML with box plots of HV and IGD per solver arm (AOO / Random /
GA / PSO / ALNS), annotated with the Kruskal-Wallis p-value across arms.

SAFE/ADDITIVE: read-only over the JSON; never touches the MATLAB solver. If the
data file is absent (e.g. stageB run not yet executed), prints a friendly hint
instead of crashing.

Usage:
    python viz/plotly_threeobj_box.py -i logs/stageB_sota.json -o figures/threeobj_box.html
"""
import argparse
import json
import os
import sys

import numpy as np
import plotly.graph_objects as go


def load(path):
    if not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-i", "--input", default="logs/stageB_sota.json")
    ap.add_argument("-o", "--out", default="figures/threeobj_box.html")
    args = ap.parse_args()

    data = load(args.input)
    if data is None:
        print(f"[plotly_threeobj_box] data file not found: {args.input}\n"
              f"  Run tests.stageB_sota (e.g. `cmd /c _cc_stageB_sota.bat`) first to "
              f"produce it, then re-run this script.", file=sys.stderr)
        return

    # 适配 tests.stageB_sota.m 的真实输出 (out.hv / out.igd / out.kruskalwallis_p)。
    # 字段为分 arm 的 N×1 数组, 非 'arms' 列表——避免与导出契约混淆。
    hv = data.get("hv", {})
    igd = data.get("igd", {})
    if not hv:
        print(f"[plotly_threeobj_box] no 'hv' in {args.input} (expected stageB_sota.json)", file=sys.stderr)
        return
    arm_order = ["aoo", "random", "ga", "pso", "alns"]
    names = [a for a in arm_order if a in hv]
    hv_lists = [np.asarray(hv[a], dtype=float).ravel() for a in names]
    igd_lists = [np.asarray(igd[a], dtype=float).ravel() for a in names if a in igd] \
        if igd else [np.array([]) for _ in names]

    # Kruskal-Wallis p (stageB 输出为标量, 非 struct)
    kw_p = data.get("kruskalwallis_p", None)
    kw_h = data.get("kruskalwallis_h", None)

    def box_trace(values_list, title):
        fig = go.Figure()
        for nm, vals in zip(names, values_list):
            if len(vals) == 0:
                continue
            fig.add_trace(go.Box(y=vals, name=nm, boxpoints="all", jitter=0.4,
                                 marker=dict(size=4), showlegend=False))
        p_txt = f"Kruskal-Wallis p = {kw_p:.2e}" if kw_p is not None else "Kruskal-Wallis p = n/a"
        fig.update_layout(
            title=f"{title} by solver arm<br><sub>{p_txt} (group difference across arms)</sub>",
            yaxis_title=title,
            template="plotly_white", height=480,
            xaxis_title="solver arm",
        )
        return fig

    # combine side by side into one HTML via subplots
    from plotly.subplots import make_subplots
    kw_str = f" — KW p={kw_p:.2e}" if kw_p is not None else ""
    combined = make_subplots(rows=1, cols=2, subplot_titles=(
        "HV (higher better)" + kw_str,
        "IGD (lower better)" + kw_str,
    ))
    for nm, vals in zip(names, hv_lists):
        if len(vals) == 0:
            continue
        combined.add_trace(go.Box(y=vals, name=nm, boxpoints="all", jitter=0.4,
                                  marker=dict(size=4), showlegend=False), row=1, col=1)
    for nm, vals in zip(names, igd_lists):
        if len(vals) == 0:
            continue
        combined.add_trace(go.Box(y=vals, name=nm, boxpoints="all", jitter=0.4,
                                  marker=dict(size=4), showlegend=False), row=1, col=2)
    combined.update_layout(
        title_text="Three-objective competitiveness (Stage B evidence)<br>"
                   "<sub>Per-arm HV/IGD distributions; Kruskal-Wallis tests group differences. "
                   "Source: logs/stageB_sota.json</sub>",
        template="plotly_white", height=520,
    )
    combined.write_html(args.out)
    print(f"[plotly_threeobj_box] wrote {args.out} ({len(names)} arms: {', '.join(names)})")


if __name__ == "__main__":
    main()
