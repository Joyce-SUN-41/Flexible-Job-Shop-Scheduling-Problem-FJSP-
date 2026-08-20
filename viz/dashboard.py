#!/usr/bin/env python3
"""Stage G - Interactive Streamlit dashboard for the FJSP LLMAOO solver.

Consumes the JSON contracts exported by exports/export_result_json.m and
exports/export_replay_json.m (produced by stage9 / stageF_run):

  - results_<date>.json        : final schedule + per-run convergence
  - *_conv_r<k>.json           : one convergence file per independent run
  - replay_<date>.json         : dynamic rescheduling event frames

This file is ADDITIVE: it only reads JSON, never touches the MATLAB solver,
so it cannot regress any numerical result. Run with:

    pip install -r viz/requirements.txt
    streamlit run viz/dashboard.py

Optional --result / --replay flags (or the in-app file picker) select data.
"""

import argparse
import glob
import fnmatch
import json
import os
from datetime import datetime

import numpy as np
import plotly.graph_objects as go

# NOTE: streamlit import is deferred so that importing this module for a
# syntax/static check (e.g. python -m py_compile) does not require streamlit
# to be installed. The real import lives inside main().


def _load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _walk_glob(root_dir, pattern):
    """Recursively find files matching `pattern` under root_dir (results/ now
    holds scenario subdirs, so discovery must recurse). ADDITIVE: keeps flat
    roots (logs/figures/.) as before."""
    hits = []
    for cur, _dirs, files in os.walk(root_dir):
        for fn in files:
            if glob.fnmatch.fnmatch(fn, pattern):
                hits.append(os.path.join(cur, fn))
    return sorted(hits)


# Patterns for the real exported result/replay contracts. The solver emits
# scenario-named files (tevc_full_result.json, hot_full_result.json,
# stageF_result.json, fullchain_result.json, ...) plus the generic
# results_<date>.json / replay_<date>.json from llmaoo(EXPORT_JSON=true).
_RESULT_PATTERNS = ("results_*.json", "*_result.json", "tevc_*.json",
                    "hot_*.json", "stageF_*.json", "stage5_*.json",
                    "fullchain_*.json", "llm_gain_quant.json")
_REPLAY_PATTERNS = ("replay_*.json", "*_replay.json")


def discover_results(root=".", extra_dirs=None):
    """Return list of result json paths found under root and extra_dirs.

    Recurses into subdirs (e.g. results/tevc_submission/) so reorganized
    outputs are still discoverable; keeps legacy flat roots too.
    """
    dirs = [root, "logs", "figures", "results"]
    if extra_dirs:
        dirs = extra_dirs + dirs
    found = []
    for d in dirs:
        if not os.path.isdir(d):
            continue
        for pat in _RESULT_PATTERNS:
            found.extend(_walk_glob(d, pat))
    # de-dup preserving order
    seen = set()
    out = []
    for p in found:
        ap = os.path.abspath(p)
        if ap not in seen:
            seen.add(ap)
            out.append(p)
    return out


def discover_replays(root=".", extra_dirs=None):
    dirs = [root, "logs", "figures", "results"]
    if extra_dirs:
        dirs = extra_dirs + dirs
    found = []
    for d in dirs:
        if not os.path.isdir(d):
            continue
        for pat in _REPLAY_PATTERNS:
            found.extend(_walk_glob(d, pat))
    seen = set()
    out = []
    for p in found:
        ap = os.path.abspath(p)
        if ap not in seen:
            seen.add(ap)
            out.append(p)
    return out


def _normalize_schedule(sched, cols=("job", "op", "machine", "start", "finish", "duration")):
    """Coerce the exported `schedule` field into a list of dicts.

    export_result_json.m writes schedule as an array-of-arrays
    [[job,op,machine,start,finish,duration], ...] (not list-of-dicts), so the
    raw JSON decodes to list[list]. Handle both that and the list-of-dicts form
    (and the MATLAB struct-array -> dict-of-column-arrays form) so the Gantt /
    Replay tabs never crash on a legitimately exported file.
    """
    if not sched:
        return []
    if isinstance(sched, dict):
        n = len(sched[cols[0]])
        return [{c: sched[c][i] for c in cols} for i in range(n)]
    if isinstance(sched[0], dict):
        return sched
    return [dict(zip(cols, row)) for row in sched]


def make_gantt_figure(result):
    """Build a Plotly Gantt figure from a result JSON dict."""
    ops = _normalize_schedule(result.get("schedule", []))
    fig = go.Figure()
    colors = {}
    palette = [
        "#4C78A8", "#F58518", "#54A24B", "#E45756", "#72B7B2",
        "#EECA3B", "#B279A2", "#FF9DA6", "#9D755D", "#BAB0AC",
    ]
    for op in ops:
        j = op.get("job", 0)
        m = op.get("machine", 0)
        st = op.get("start", 0.0)
        en = op.get("finish", 0.0)
        dur = max(en - st, 0.0)
        c = colors.setdefault(j, palette[(int(j) - 1) % len(palette)])
        fig.add_bar(
            x=[dur],
            y=[f"M{m}"],
            base=[st],
            orientation="h",
            marker_color=c,
            name=f"J{j}",
            legendgroup=f"J{j}",
            showlegend=(j not in colors),
            hovertemplate=(
                f"Job {j} Op {op.get('op', 0)}<br>"
                f"Machine {m}<br>Start {st:.1f}<br>End {en:.1f}<extra></extra>"
            ),
        )
    fig.update_layout(
        barmode="overlay",
        title="Gantt - Final Schedule",
        xaxis_title="Time",
        yaxis_title="Machine",
        height=520,
        margin=dict(l=60, r=20, t=40, b=40),
        legend_title="Job",
    )
    return fig


def make_convergence_figure(result, conv_paths):
    """Convergence: REAL makespan (primary) + +/- std band across runs.

    Independent-run JSON files (e.g. hot_conv_*.json) use the same contract as
    the primary result (export_result_json.m). We prefer the REAL makespan trace
    ("trace_makespan") so the y-axis reads in real scheduling-time units instead
    of the normalized weighted objective (0.x). Falls back to the normalized
    "trace_best" only when real makespan is unavailable (older exports), labelled
    clearly as normalized.
    """
    def _pick(d, real_key="trace_makespan", norm_key="trace_best"):
        if d.get(real_key):
            return np.array(d[real_key], dtype=float), False
        tb = d.get(norm_key) or d.get("convergence", {}).get(norm_key, [])
        if tb:
            return np.array(tb, dtype=float), True
        return None, False

    fig = go.Figure()
    runs = []
    any_norm = False
    for cp in conv_paths:
        try:
            d = _load_json(cp)
            arr, is_norm = _pick(d)
            if arr is not None:
                runs.append(arr)
                any_norm = any_norm or is_norm
        except Exception:
            continue
    if runs:
        maxlen = max(len(r) for r in runs)
        padded = [np.pad(r, (0, maxlen - len(r)), constant_values=np.nan) for r in runs]
        mat = np.vstack(padded)
        mean = np.nanmean(mat, axis=0)
        std = np.nanstd(mat, axis=0)
        x = list(range(maxlen))
        fig.add_trace(go.Scatter(x=x, y=mean + std, mode="lines",
                                 line=dict(width=0), showlegend=False, hoverinfo="skip"))
        fig.add_trace(go.Scatter(x=x, y=mean - std, mode="lines",
                                 line=dict(width=0), fill="tonexty",
                                 fillcolor="rgba(76,120,168,0.25)",
                                 name="std band", hoverinfo="skip"))
        fig.add_trace(go.Scatter(x=x, y=mean, mode="lines",
                                 name="mean (runs)", line=dict(color="#4C78A8")))
    # primary result: prefer real makespan
    prim, prim_norm = _pick(result)
    if prim is not None:
        fig.add_trace(go.Scatter(x=list(range(len(prim))), y=prim, mode="lines",
                                 name="primary (real makespan)" if not prim_norm
                                 else "primary (normalized)",
                                 line=dict(color="#E45756", dash="dot")))
    ytitle = "Makespan (real time)" if not (any_norm and prim_norm) else "Objective (normalized)"
    fig.update_layout(
        title="Convergence (best makespan over generations)",
        xaxis_title="Generation",
        yaxis_title=ytitle,
        height=460,
        margin=dict(l=60, r=20, t=40, b=40),
    )
    return fig


def make_replay_figure(replay, frame_idx=0):
    """Render a single replay frame as a Gantt-like bar chart.

    The replay JSON contract (exports/export_replay_json.m) puts each frame's
    bars under the key "schedule" (array of [job,op,machine,start,finish,dur])
    plus "type"/"time"/"desc" metadata - NOT "bars"/"events". Read from the
    real contract so the Replay tab actually renders instead of an empty plot.
    """
    frames = replay.get("frames", [])
    if not frames:
        fig = go.Figure()
        fig.update_layout(title="Replay - no frames")
        return fig
    fi = min(frame_idx, len(frames) - 1)
    fr = frames[fi]
    cols = ["job", "op", "machine", "start", "finish", "duration"]
    sched = fr.get("schedule", [])
    if sched and isinstance(sched[0], dict):
        rows = sched
    else:
        rows = [dict(zip(cols, row)) for row in sched]
    palette = [
        "#4C78A8", "#F58518", "#54A24B", "#E45756", "#72B7B2",
        "#EECA3B", "#B279A2", "#FF9DA6", "#9D755D", "#BAB0AC",
    ]
    job_color = {}
    fig = go.Figure()
    for r in rows:
        j = int(r.get("job", 0)); m = int(r.get("machine", 0))
        s = float(r.get("start", 0.0)); f = float(r.get("finish", 0.0))
        job_color.setdefault(j, palette[(j - 1) % len(palette)])
        fig.add_bar(x=[max(f - s, 0.0)], y=[f"M{m}"], base=[s], orientation="h",
                    marker_color=job_color[j], showlegend=False,
                    hovertemplate=f"Job {j} Op {int(r.get('op', 0))}<br>"
                                  f"M{m}<br>{s:.1f}-{f:.1f}<extra></extra>")
    title = f"Replay frame {fi+1}/{len(frames)}"
    etype = fr.get("type"); etime = fr.get("time"); edesc = fr.get("desc")
    info = []
    if etime is not None:
        info.append(f"t={etime}")
    if etype:
        info.append(str(etype))
    if edesc:
        info.append(str(edesc))
    if info:
        title += " | " + " ".join(info)
    fig.update_layout(barmode="overlay", title=title, xaxis_title="Time",
                      yaxis_title="Machine", height=480,
                      margin=dict(l=60, r=20, t=40, b=40))
    return fig


def _frame_makespan(fr):
    """Stage4: robustly compute a frame's makespan from its schedule contract.

    export_replay_json.m serializes each frame as a MATLAB struct: `schedule`
    is an array-of-arrays [[job,op,machine,start,finish,duration], ...]. A frame
    may also carry an explicit scalar `makespan` (set for the baseline by the
    Stage4 dynamic_replay elite path). Prefer that when present; otherwise take
    max(finish) over the schedule rows so the comparison view never crashes.
    """
    mk = fr.get("makespan")
    if mk is not None and isinstance(mk, (int, float)):
        return float(mk)
    sched = fr.get("schedule", [])
    if not sched:
        return 0.0
    finishes = []
    if isinstance(sched[0], dict):
        for r in sched:
            finishes.append(float(r.get("finish", 0.0)))
    else:
        for row in sched:
            # columns: job, op, machine, start, finish, duration  (index 4 = finish)
            try:
                finishes.append(float(row[4]))
            except (IndexError, TypeError):
                continue
    return max(finishes) if finishes else 0.0


def make_dynamic_compare_figure(replay):
    """Stage4: static(baseline) vs dynamic(rescheduled) makespan comparison.

    Renders a bar chart of makespan per replay frame, highlighting the baseline
    (frame 0, real AOO-optimal schedule) against each perturbed/rescheduled
    frame, so the cost of disturbance -> reactive reschedule is visible. This is
    the dashboard-side "digital-twin linkage" comparison view.
    """
    frames = replay.get("frames", [])
    if not frames:
        fig = go.Figure()
        fig.update_layout(title="Dynamic compare - no frames")
        return fig
    labels, makespans, colors = [], [], []
    base_color = "#4C78A8"
    event_color = "#E45756"
    for i, fr in enumerate(frames):
        mk = _frame_makespan(fr)
        etype = fr.get("type", "frame")
        etime = fr.get("time", "")
        label = f"t={etime}" if etime != "" else f"frame {i+1}"
        if i == 0:
            label = "baseline"
        labels.append(label)
        makespans.append(mk)
        colors.append(base_color if i == 0 else event_color)
    fig = go.Figure()
    fig.add_bar(x=labels, y=makespans, marker_color=colors,
                text=[f"{m:.1f}" for m in makespans], textposition="outside")
    # delta annotations: each event frame vs baseline
    base_mk = makespans[0] if makespans else 0.0
    deltas = [m - base_mk for m in makespans]
    fig.add_trace(go.Scatter(x=labels, y=makespans, mode="lines+markers",
                             line=dict(color="#333", width=1, dash="dot"),
                             showlegend=False, hoverinfo="skip"))
    title = "Dynamic reschedule: baseline vs perturbed makespan"
    if len(makespans) > 1:
        worst = max(deltas[1:])
        title += f"  (max delta +{worst:.1f})"
    fig.update_layout(title=title, xaxis_title="Event", yaxis_title="Makespan",
                      height=460, margin=dict(l=60, r=20, t=40, b=40),
                      legend_title="Phase")
    return fig


def make_pareto_figure(result):
    """Stage-Refine: Pareto-front scatter (real makespan vs real load imbalance).

    Reads `result["pareto"]["mk"|"lb"]` (REAL makespan / loadUnb, exported by
    export_result_json.m) for the axes. Energy colour axis: prefers the explicit
    `pareto["energy_n"]` field introduced in contract v1.2 (Stage4 pareto-cleanup);
    falls back to the 3rd dim of `obj3` for legacy contracts (<1.2). When no finite
    energy dimension exists (2-obj runs export `energy_n=[]`), uses a neutral
    single colour. Returns None when the result has no Pareto data.
    """
    p = result.get("pareto")
    if not p or not p.get("mk"):
        return None
    mk = np.asarray(p["mk"], dtype=float).ravel()
    lb = np.asarray(p["lb"], dtype=float).ravel()
    # Energy colour axis: explicit energy_n (v>=1.2) preferred; legacy obj3[:,2] fallback.
    en = None
    en_field = p.get("energy_n")
    if en_field is not None and np.asarray(en_field).size > 0:
        col = np.asarray(en_field, dtype=float).ravel()
        if np.isfinite(col).any():
            en = col
    if en is None:
        # Legacy fallback: read energy from obj3 3rd column when present and finite.
        obj3 = p.get("obj3")
        if obj3 is not None:
            Z3 = np.asarray(obj3, dtype=float)
            if Z3.ndim == 2 and Z3.shape[1] >= 3:
                col = Z3[:, 2]
                if np.isfinite(col).any():
                    en = col
    has_energy = en is not None
    if has_energy:
        color_kw = dict(color=en, colorscale="Viridis", showscale=True,
                         colorbar=dict(title="Energy (norm)"))
        hover = ("makespan=%{x:.1f}<br>loadUnb=%{y:.1f}<br>energy=%{marker.color:.3f}<extra></extra>")
    else:
        color_kw = dict(color="#4C78A8", showscale=False)
        hover = "makespan=%{x:.1f}<br>loadUnb=%{y:.1f}<extra></extra>"

    fig = go.Figure()
    fig.add_scatter(
        x=mk, y=lb, mode="markers",
        marker=dict(size=8, **color_kw),
        hovertemplate=hover,
        name="Pareto solutions",
    )
    n = len(mk)
    title = (f"Pareto Front (real makespan vs loadUnb, n={n})"
             + ("  [3-obj: energy colour]" if has_energy else "  [2-obj]"))
    fig.update_layout(
        title=title,
        xaxis_title="Makespan (lower better)",
        yaxis_title="Load imbalance = max-min load (lower better)",
        height=520,
        margin=dict(l=60, r=20, t=40, b=40),
    )
    return fig


def make_overview_table(result_paths, replay_paths):
    """Stage5: aggregate KPIs across all discovered result/replay exports.

    Produces a Plotly table summarizing, per exported file, the problem,
    makespan, load imbalance, runtime, and (for replays) the baseline vs
    worst-event makespan delta. This is the single "all-shapes" overview
    view required by Stage5 (static + dynamic + 3-obj + digital-twin linkage)
    without touching any existing tab.
    """
    import pandas as pd  # deferred; only needed for the overview table

    rows = []
    for p in result_paths:
        try:
            d = _load_json(p)
        except Exception:
            continue
        prob = d.get("problem", {})
        mk = d.get("makespan")
        if mk is None:
            sched = d.get("schedule", [])
            mk = max((op.get("finish", 0.0) for op in sched), default=None) if sched else None
        tb = d.get("trace_best", []) or d.get("convergence", {}).get("trace_best", [])
        rows.append({
            "file": os.path.basename(p),
            "shape": "static/3-obj" if prob.get("has_energy") else "static",
            "problem": prob.get("name", "n/a"),
            "jobs": prob.get("nJob"),
            "mks": mk,
            "loadUnb": d.get("loadUnb"),
            "runtime_s": d.get("elapsed_sec"),
            # 阶段一 P0: overview 的 final_best 统一为真实 makespan（与卡片语义一致），
            # 不再用归一化 trace_best 末值（tb[-1]）造成双语义误导。
            "final_best": mk,
            "dyn_delta": None,
        })
    for p in replay_paths:
        try:
            d = _load_json(p)
        except Exception:
            continue
        frames = d.get("frames", [])
        if not frames:
            continue
        mks_list = [_frame_makespan(fr) for fr in frames]
        base = mks_list[0] if mks_list else None
        worst = max(mks_list[1:]) if len(mks_list) > 1 else base
        rows.append({
            "file": os.path.basename(p),
            "shape": "dynamic/replay",
            "problem": d.get("desc", "n/a"),
            "jobs": None,
            "mks": worst,
            "loadUnb": None,
            "runtime_s": None,
            "final_best": None,
            "dyn_delta": (worst - base) if (base is not None and worst is not None) else None,
        })
    # Stage5: also surface the full-benchmark and SOTA-compare artifacts so the
    # Overview tab doubles as the submission evidence summary.
    for cand in ("logs/stage5_benchmark.json", "stage5_benchmark.json",
                 "logs/stage5_sota_compare.json", "stage5_sota_compare.json"):
        if not os.path.isfile(cand):
            continue
        try:
            d = _load_json(cand)
        except Exception:
            continue
        if "stage5_benchmark" in cand:
            for r in d:
                # 阶段一 P0: 修正字段解析（stage7_run 导出 aoo_best / bks / gap_best_pct，
                # 旧代码误读 r.get("aoo") 始终为 None）。并把"求得值"与"BKS 理论最优"
                # 分到两列且列名显式区分，避免 final_best 被误读为求得值。
                aoo_best = r.get("aoo_best")
                bks = r.get("bks")
                gap = r.get("gap_best_pct")
                rows.append({
                    "file": "stage5_benchmark",
                    "shape": "benchmark (MK)",
                    "problem": r.get("inst", "n/a"),
                    "jobs": r.get("nJob"),
                    "mks": aoo_best,            # AOO 求得的最优 makespan
                    "loadUnb": None,
                    "runtime_s": None,
                    "final_best": aoo_best,     # 同表统一为"求得值"，BKS 单独成列
                    "bks": bks,                 # 理论最优（显式列，避免混义）
                    "dyn_delta": gap,           # gap_best_pct（%）
                })
        else:  # sota compare: one row per variant
            mk = d.get("mk", {})
            for vn in mk:
                best_v = float(min(mk[vn])) if len(mk[vn]) else None
                worst_v = float(max(mk[vn])) if len(mk[vn]) else None
                rows.append({
                    "file": "stage5_sota",
                    "shape": f"SOTA/{vn}",
                    "problem": d.get("prob", {}).get("name", "MK01"),
                    "jobs": d.get("prob", {}).get("nJob"),
                    "mks": best_v,            # 求得最优 makespan
                    "loadUnb": None,
                    "runtime_s": None,
                    # C3 修正: final_best 与 benchmark 行统一为"求得最优值"(min)，
                    # 不再取 max(mk) 造成同列语义反向(最差)。最差成绩单独成列 sota_worst。
                    "final_best": best_v,
                    "sota_worst": worst_v,    # 显式最差，与 final_best 区分
                    "dyn_delta": None,
                })
    if not rows:
        fig = go.Figure()
        fig.update_layout(title="Overview - no exports found")
        return fig
    df = pd.DataFrame(rows)
    fig = go.Figure(data=[go.Table(
        header=dict(values=list(df.columns),
                    fill_color="#4C78A8", font_color="white",
                    line_color="lightgrey", align="left"),
        cells=dict(values=[df[c] for c in df.columns],
                   fill_color="white", line_color="lightgrey", align="left"))])
    fig.update_layout(title="Stage5 Overview - all exported shapes (static / dynamic / 3-obj / twin)",
                      height=max(120, 40 + 30 * len(rows)),
                      margin=dict(l=20, r=20, t=40, b=20))
    # C3 修正: 表头列义澄清（final_best 在 static/benchmark/SOTA 行均=求得最优值；
    # SOTA 行的 sota_worst 单独列示最差成绩；bks=理论最优不与 final_best 混义）。
    fig.add_annotation(
        text=("列说明：mks/final_best = 求得最优值(各算法同义)；bks = 理论最优(BKS)；"
              "sota_worst = SOTA 行各 variant 最差成绩；dyn_delta = gap_best_pct(%)。"
              "static 行的 final_best 即真实 makespan。"),
        showarrow=False, xref="paper", yref="paper", x=0, y=-0.08,
        xanchor="left", yanchor="top", font=dict(size=11, color="#555"))
    return fig


def summary_cards(result):
    """Return a dict of KPI values for the sidebar / top cards.

    NOTE: export_result_json.m writes scalar objectives at the top level
    (makespan / elapsed_sec) and problem dims inside result["problem"]
    (nJob/nMachine/nOp), NOT under a "meta" key. Read from those fields
    directly so the metric cards are populated instead of showing n/a.
    """
    prob = result.get("problem", {})
    sched = result.get("schedule", [])
    makespan = result.get("makespan")
    if makespan is None and sched:
        makespan = max((op.get("end", 0.0) for op in sched), default=0.0)
    # 阶段一 P0: final_best 统一为真实 makespan（已在顶层导出），避免与归一化
    # trace_best 末值产生"真实 makespan vs 归一化 final_best"双语义误导。
    # 归一化收敛末值可由 trace_makespan 末值（真实）或更下方收敛页读取。
    return {
        "makespan": makespan,
        "num_jobs": prob.get("nJob"),
        "num_machines": prob.get("nMachine"),
        "num_ops": prob.get("nOp"),
        "runtime_s": result.get("elapsed_sec"),
        "final_best": makespan,   # 真实 makespan（与卡片 Makespan 一致）
        "three_obj": bool(prob.get("has_energy", False)),
    }


def main():
    import streamlit as st  # real import (deferred until run)

    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--result", default=None)
    parser.add_argument("--replay", default=None)
    args, _ = parser.parse_known_args()

    st.set_page_config(page_title="FJSP LLMAOO Dashboard", layout="wide")
    st.title("FJSP LLMAOO - Interactive Results Dashboard")
    st.caption("Stage G: consumes JSON contracts from stage9 / stageF (read-only, ADDITIVE)")

    result_paths = discover_results()
    replay_paths = discover_replays()
    if args.result and args.result not in result_paths:
        result_paths.insert(0, args.result)
    if args.replay and args.replay not in replay_paths:
        replay_paths.insert(0, args.replay)

    col1, col2 = st.columns([1, 2])
    with col1:
        # E5 (stage5): surface contract_version + generated time in the selector
        # label so historically-coexisting results_*.json are easier to tell apart
        # (dashboard already warns on legacy/<1.2 contracts; this just aids picking).
        def _label(p):
            try:
                d = _load_json(p)
                cv = d.get("contract_version", "?")
                gen = d.get("generated", "")
                sce = d.get("scenario", "")
                tag = f"v{cv}"
                if sce:
                    tag += f" · {sce}"
                if gen:
                    tag += f" · {gen}"
                return f"{os.path.basename(p)}  ({tag})"
            except Exception:
                return os.path.basename(p)
        result_labels = [_label(p) for p in result_paths]
        sel_idx = 0 if result_paths else -1
        sel_label = st.selectbox("Result JSON", result_labels, index=sel_idx)
        sel_result = result_paths[result_labels.index(sel_label)] if result_labels else None
    with col2:
        sel_replay = st.selectbox("Replay JSON (optional)", ["(none)"] + replay_paths,
                                  index=0)

    if not sel_result:
        st.warning("No results_*.json found. Run tests.stageF_run or stage9 to export one.")
        return

    result = _load_json(sel_result)
    cards = summary_cards(result)

    # provenance line (pure display): source file, export version, generated time
    src = os.path.basename(sel_result)
    ver = result.get("version", "n/a")
    gen = result.get("generated", "n/a")
    cv = result.get("contract_version", None)
    prov = f"Source: `{src}`  |  contract v{ver}  |  generated {gen}"
    # 阶段一 P0: 契约版本检查——无 contract_version 或 <1.1 视为旧归一化格式，
    # 其 makespan 为归一化值(0.x)不可当真实刻度，明确告警避免误读。
    if cv is None or str(cv) < "1.1":
        prov += "  ⚠ legacy/normalized format (makespan not real-scale)"
    st.caption(prov)

    k1, k2, k3, k4 = st.columns(4)
    k1.metric("Makespan", f"{cards['makespan']:.1f}" if cards["makespan"] is not None else "n/a")
    k2.metric("Jobs x Machines",
              f"{cards['num_jobs']} x {cards['num_machines']}" if cards["num_jobs"] else "n/a")
    k3.metric("Operations", cards["num_ops"] if cards["num_ops"] else "n/a")
    k4.metric("Runtime (s)", f"{cards['runtime_s']:.1f}" if cards["runtime_s"] else "n/a")

    if cards["three_obj"]:
        st.info("Three-objective (makespan + load imbalance + energy) mode active.")

    tab0, tab1, tab2, tab3, tab4, tab5 = st.tabs(
        ["Overview", "Gantt", "Convergence", "Replay (dynamic)", "Dynamic Compare", "Pareto (3-obj)"])

    with tab0:
        # Stage5: single aggregate view of every exported shape (static / dynamic /
        # 3-obj / digital-twin linkage). Pure display, ADDITIVE over the other tabs.
        st.plotly_chart(make_overview_table(result_paths, replay_paths),
                        use_container_width=True)
        st.caption("Aggregates recently exported results_*.json and replay_*.json "
                   "from ./, logs/, figures/. MK01 is the built-in benchmark; "
                   "MK02-10 require standard .fjs instance files (see stage5_run).")

    with tab1:
        st.plotly_chart(make_gantt_figure(result), use_container_width=True)

    with tab2:
        # collect sibling convergence files for the same export
        base = os.path.basename(sel_result)
        stem = base.replace("results_", "").replace(".json", "")
        conv_dir = os.path.dirname(sel_result)
        conv_paths = sorted(glob.glob(os.path.join(conv_dir, f"*_conv_*{stem}*.json")))
        if not conv_paths:
            conv_paths = sorted(glob.glob(os.path.join(conv_dir, f"*_conv_*.json")))
        st.plotly_chart(make_convergence_figure(result, conv_paths), use_container_width=True)

    with tab3:
        if sel_replay and sel_replay != "(none)":
            replay = _load_json(sel_replay)
            frames = replay.get("frames", [])
            if frames:
                fi = st.slider("Frame", 0, len(frames) - 1, 0)
                st.plotly_chart(make_replay_figure(replay, fi), use_container_width=True)
                # each frame carries type/time/desc; summarize the perturbation
                # timeline from the contract instead of a non-existent "meta".
                fr = frames[fi]
                st.write("Frame meta:",
                         f"type={fr.get('type','n/a')}, "
                         f"time={fr.get('time','n/a')}, "
                         f"desc={fr.get('desc','n/a')} "
                         f"({fi+1}/{len(frames)})")
            else:
                st.write("Replay file has no frames.")
        else:
            st.info("Select a replay JSON above to visualize dynamic rescheduling.")

    with tab4:
        # Stage4: static(baseline, real AOO elite) vs dynamic(rescheduled) makespan
        # comparison view - the dashboard-side linkage to the 3D digital twin.
        if sel_replay and sel_replay != "(none)":
            replay = _load_json(sel_replay)
            st.plotly_chart(make_dynamic_compare_figure(replay), use_container_width=True)
            src_desc = replay.get("desc", "")
            if src_desc:
                st.caption(f"Replay source: {src_desc}")
            st.info("Baseline = real AOO-optimal schedule; event frames show the "
                    "makespan after reactive rescheduling. Compare with the 3D "
                    "digital-twin HTML (python viz/digital_twin.py <replay>.json).")
        else:
            st.info("Select a replay JSON above to compare baseline vs rescheduled "
                    "makespan (Stage4 dynamic reschedule linkage).")

    with tab5:
        # Stage-Refine: Pareto front view for the three-objective (NSGA-III) mode.
        # Reads the `pareto` (mk/lb/obj) and `quality` (HV/IGD) fields exported by
        # export_result_json when AOO_THREE_OBJ is active. ADDITIVE / non-fatal:
        # shows a clear hint when the selected result is from a 2-obj run.
        fig = make_pareto_figure(result)
        if fig is not None:
            st.plotly_chart(fig, use_container_width=True)
            q = result.get("quality", {})
            if q:
                hv = q.get("HV", q.get("hv"))
                igd = q.get("IGD", q.get("igd"))
                cols = st.columns(2)
                cols[0].metric("Hypervolume (HV)", f"{hv:.4f}" if hv is not None else "n/a")
                cols[1].metric("IGD", f"{igd:.4f}" if igd is not None else "n/a")
                st.caption("NSGA-III quality indicators (higher HV / lower IGD = better "
                           "Pareto approximation). Populated only for 3-obj runs.")
        else:
            st.info("No Pareto data in this result. Run a three-objective solve "
                     "(e.g. tests.fullchain_demo or AOO_DEFAULT_SCENARIO='multi') "
                     "and re-export to visualize the NSGA-III Pareto front + HV/IGD.")


if __name__ == "__main__":
    main()
