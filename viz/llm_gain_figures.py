#!/usr/bin/env python3
"""llm_gain_figures.py — Stage2 P2 (任务 2.2) three-arm LLM-gain comparison figures.

Reads results/tevc_llm_gain/tevc_llm_gain.json (produced by tests.tevc_llm_gain) and
renders a grouped bar chart of final makespan per instance for the three arms
(aoo / modulate / full). If the JSON carries an `env_state.mode == 'offline_honest'`
(or the three arms are identical), the figure is annotated as an OFFLINE-HONEST state
where full == modulate == aoo (no fabricated online gain). When a real online run is
later produced (DEEPSEEK_API_KEY + reachable API), the same script renders the true
differentiation and the significance table.

SAFE/ADDITIVE: read-only visualization; never modifies solver numerics or the JSON.

Usage:
    python viz/llm_gain_figures.py
    python viz/llm_gain_figures.py -i results/tevc_llm_gain/tevc_llm_gain.json -o figures/llm_gain_compare.html
"""
import argparse
import json
import os
import sys

import plotly.graph_objects as go


def load(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def main():
    ap = argparse.ArgumentParser()
    here = os.path.dirname(os.path.abspath(__file__))
    default_in = os.path.join(here, "..", "results", "tevc_llm_gain", "tevc_llm_gain.json")
    ap.add_argument("-i", "--in", default=default_in, help="tevc_llm_gain.json path")
    ap.add_argument("-o", "--out", default="figures/llm_gain_compare.html")
    args = ap.parse_args()

    if not os.path.exists(args.in):
        print(f"[llm_gain_figures] input not found: {args.in}", file=sys.stderr)
        print("  Run tests.tevc_llm_gain (with DEEPSEEK_API_KEY) to produce it.", file=sys.stderr)
        return

    d = load(args.in)
    arms = ["aoo", "modulate", "full"]
    insts = list(d.keys())

    # Determine honesty state: if any arm has identical mean across all three -> offline honest.
    offline_honest = True
    for inst in insts:
        rec = d[inst]
        means = [rec.get(a, {}).get("mean", float("nan")) for a in arms]
        if not all(m == means[0] for m in means):
            offline_honest = False
            break

    fig = go.Figure()
    colors = {"aoo": "#4C78A8", "modulate": "#F58518", "full": "#54A24B"}
    for arm in arms:
        ys = [d[inst].get(arm, {}).get("mean", float("nan")) for inst in insts]
        fig.add_bar(name=arm, x=insts, y=ys, marker_color=colors[arm])

    subtitle = ("OFFLINE-HONEST STATE: full == modulate == aoo (no online LLM gain claimed); "
               "gain=0 is an environment fact, not a defect. Re-run tests.tevc_llm_gain with "
               "DEEPSEEK_API_KEY + reachable API for the true three-arm differentiation."
               if offline_honest else
               "ONLINE STATE: three arms differentiated; see significance table in the JSON.")

    fig.update_layout(
        title=f"LLM-Gain Three-Arm Comparison (makespan mean)<br>"
              f"<sub>{subtitle}</sub>",
        barmode="group",
        xaxis_title="Brandimarte instance",
        yaxis_title="Mean makespan (lower better)",
        height=560, margin=dict(l=60, r=20, t=90, b=60),
        legend=dict(orientation="h", y=1.02, x=0),
    )
    if offline_honest:
        fig.add_annotation(
            text="OFFLINE HONEST<br>full ≡ modulate ≡ aoo",
            xref="paper", yref="paper", x=0.5, y=0.5,
            showarrow=False, font=dict(size=22, color="rgba(180,80,80,0.35)"),
            bgcolor="rgba(0,0,0,0)",
        )

    out_dir = os.path.dirname(args.out)
    if out_dir and not os.path.exists(out_dir):
        os.makedirs(out_dir, exist_ok=True)
    fig.write_html(args.out)
    print(f"[llm_gain_figures] wrote {args.out}  (offline_honest={offline_honest}, {len(insts)} instances)")


if __name__ == "__main__":
    main()
