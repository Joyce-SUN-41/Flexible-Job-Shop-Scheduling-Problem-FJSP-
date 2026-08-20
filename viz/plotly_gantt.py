#!/usr/bin/env python3
"""Stage9 visualization (batch 1): interactive Gantt chart from LLMAOO result JSON.

Reads results_<date>.json produced by MATLAB export_result_json (cfg.EXPORT_JSON=true)
and renders an interactive HTML Gantt chart: hover for operation detail, zoom the
time axis, color by job. Pure data visualization; no dependency on the solver.

Usage:
    python viz/plotly_gantt.py results_2026_08_12_*.json -o figures/gantt.html
"""
import argparse
import json
import sys

import plotly.graph_objects as go


def load_result(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def build_gantt(result, out_html):
    cols = result.get("schedule_cols", ["job", "op", "machine", "start", "finish", "duration"])
    sched = result["schedule"]
    # sched is array-of-arrays OR a struct-like object; normalize to list of dicts.
    if isinstance(sched, dict):
        # MATLAB jsondecode of struct-array -> dict of column arrays
        rows = []
        n = len(sched[cols[0]])
        for i in range(n):
            rows.append({c: sched[c][i] for c in cols})
        sched = rows
    elif sched and isinstance(sched[0], dict):
        pass
    else:
        # array-of-arrays
        sched = [dict(zip(cols, row)) for row in sched]

    fig = go.Figure()
    jobs = sorted({int(r["job"]) for r in sched})
    palette = [
        "#4C78A8", "#F58518", "#54A24B", "#E45756", "#72B7B2", "#EECA3B",
        "#B279A2", "#FF9DA6", "#9D755D", "#BAB0AC", "#86BCB6", "#D37295",
    ]
    job_color = {j: palette[(j - 1) % len(palette)] for j in jobs}

    for r in sched:
        j = int(r["job"]); op = int(r["op"]); m = int(r["machine"])
        s = float(r["start"]); f = float(r["finish"])
        fig.add_bar(
            x=[f - s], base=[s], y=[f"M{m}"],
            orientation="h",
            marker_color=job_color[j],
            hovertext=(f"Job {j} Op {op} | Machine {m}<br>"
                       f"Start {s:.1f} -> Finish {f:.1f} "
                       f"(dur {f - s:.1f})"),
            hoverinfo="text",
            showlegend=False,
            name=f"Job {j}",
        )

    fig.update_layout(
        title=(f"FJSP Gantt (makespan={result.get('makespan')}, "
               f"loadUnb={result.get('loadUnb')})"),
        xaxis_title="Time",
        yaxis_title="Machine",
        barmode="overlay",
        template="plotly_white",
        height=600,
    )
    fig.write_html(out_html)
    print(f"[plotly_gantt] wrote {out_html} ({len(sched)} operations)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("json", help="path to results_*.json")
    ap.add_argument("-o", "--out", default="figures/gantt.html")
    args = ap.parse_args()
    build_gantt(load_result(args.json), args.out)


if __name__ == "__main__":
    main()
