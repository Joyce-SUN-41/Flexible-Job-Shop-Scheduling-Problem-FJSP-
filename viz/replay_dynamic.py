#!/usr/bin/env python3
"""Stage9 visualization (batch 2): dynamic-reschedule replay animation.

Reads replay_*.json (frames produced by MATLAB dynamic_replay + export_replay_json)
and renders an animated/interactive HTML showing how the schedule evolves across
disturbance events (machine breakdown -> local reschedule). Demonstrates robustness
of the DFJSP reschedule loop.

Usage:
    python viz/replay_dynamic.py replay_*.json -o figures/replay.html
"""
import argparse
import json

import plotly.graph_objects as go


def load(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def build(replay, out_html):
    frames = replay["frames"]
    cols = ["job", "op", "machine", "start", "finish", "duration"]
    palette = [
        "#4C78A8", "#F58518", "#54A24B", "#E45756", "#72B7B2", "#EECA3B",
        "#B279A2", "#FF9DA6", "#9D755D", "#BAB0AC", "#86BCB6", "#D37295",
    ]
    job_color = {}

    fig = go.Figure()
    # initial empty traces (one per frame to animate)
    steps = []
    for fi, fr in enumerate(frames):
        sched = fr["schedule"]
        if isinstance(sched, dict):  # struct-array decode -> column arrays
            n = len(sched[cols[0]])
            rows = [{c: sched[c][i] for c in cols} for i in range(n)]
        elif sched and isinstance(sched[0], dict):
            rows = sched
        else:
            rows = [dict(zip(cols, row)) for row in sched]

        xs, bases, colors, texts, ys = [], [], [], [], []
        for r in rows:
            j = int(r["job"]); m = int(r["machine"])
            s = float(r["start"]); f = float(r["finish"])
            job_color.setdefault(j, palette[(j - 1) % len(palette)])
            xs.append(f - s); bases.append(s); colors.append(job_color[j])
            ys.append(f"M{m}")
            texts.append(f"Job {j} Op {int(r['op'])} | M{m}<br>{s:.1f}->{f:.1f}")

        trace = go.Bar(
            x=xs, base=bases, y=ys, orientation="h",
            marker_color=colors, hovertext=texts, hoverinfo="text",
            showlegend=False,
        )
        if fi == 0:
            fig.add_trace(trace)
            fig.update_layout(
                title=f"Dynamic replay: {fr['type']} @ t={fr['time']} | {fr['desc']}",
                xaxis_title="Time", yaxis_title="Machine",
                barmode="overlay", template="plotly_white", height=600,
            )
        step = dict(
            method="animate",
            args=[[f"frame{fi}"],
                  {"frame": {"duration": 1500, "redraw": True},
                   "mode": "immediate"}],
            label=f"t={fr['time']}:{fr['type']}",
        )
        steps.append(step)

    # build animation frames
    anim_frames = []
    for fi, fr in enumerate(frames):
        sched = fr["schedule"]
        if isinstance(sched, dict):
            n = len(sched[cols[0]])
            rows = [{c: sched[c][i] for c in cols} for i in range(n)]
        elif sched and isinstance(sched[0], dict):
            rows = sched
        else:
            rows = [dict(zip(cols, row)) for row in sched]
        xs, bases, colors, texts, ys = [], [], [], [], []
        for r in rows:
            j = int(r["job"]); m = int(r["machine"])
            s = float(r["start"]); f = float(r["finish"])
            xs.append(f - s); bases.append(s); colors.append(job_color[j])
            ys.append(f"M{m}")
            texts.append(f"Job {j} Op {int(r['op'])} | M{m}<br>{s:.1f}->{f:.1f}")
        anim_frames.append(go.Frame(
            data=[go.Bar(x=xs, base=bases, y=ys, orientation="h",
                         marker_color=colors, hovertext=texts, hoverinfo="text",
                         showlegend=False)],
            name=f"frame{fi}",
            layout=go.Layout(
                title=f"Dynamic replay: {fr['type']} @ t={fr['time']} | {fr['desc']}"),
        ))

    fig.frames = anim_frames
    fig.update_layout(updatemenus=[dict(type="buttons", showactive=False,
                                        buttons=[dict(label="Play",
                                                       method="animate",
                                                       args=[None,
                                                             {"frame": {"duration": 1500},
                                                              "fromcurrent": True}])])],
                      sliders=[dict(active=0, steps=steps,
                                    currentvalue={"prefix": "Frame: "})])
    fig.write_html(out_html)
    print(f"[replay_dynamic] wrote {out_html} ({len(frames)} frames)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("json")
    ap.add_argument("-o", "--out", default="figures/replay.html")
    args = ap.parse_args()
    build(load(args.json), args.out)


if __name__ == "__main__":
    main()
