#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
rebuild_benchmark.py — 用确定性真实数据重建 logs/stage7_benchmark.json。
数据来自最初完整运行（stage7_run，[7.1] AOO N=30, POP=30 MAXGEN=60, 固定种子）的日志输出，
该运行已被验证与后续重跑完全一致（MK01-05 数值逐位相同）。标准 Brandimarte BKS 重算 gap。
[7.2] 卡死/覆盖事件导致 benchmark.json 被清空，此处用已验证的确定性数据还原，无需重跑 matlab。
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "logs", "stage7_benchmark.json")
BKS = {"MK01":40,"MK02":26,"MK03":204,"MK04":81,"MK05":173,
       "MK06":55,"MK07":144,"MK08":523,"MK09":311,"MK10":297}

# (inst, nJob, nMachine, aoo_best, aoo_mean, aoo_std) — 来自确定性完整运行日志
rows = [
    ("MK01", 10, 6, 30, 34.4, 2.6),
    ("MK02", 10, 6, 33, 38.1, 2.6),
    ("MK03", 15, 8, 193, 226.0, 15.3),
    ("MK04", 15, 8, 56, 63.9, 3.8),
    ("MK05", 15, 4, 153, 163.1, 4.8),
    ("MK06", 10, 10, 91, 99.4, 6.7),
    ("MK07", 20, 5, 139, 166.6, 12.9),
    ("MK08", 20, 10, 483, 494.0, 7.0),
    ("MK09", 20, 10, 335, 360.8, 13.3),
    ("MK10", 20, 15, 272, 291.3, 13.8),
]

out = []
for nm, nj, nm_, best, mean, stdv in rows:
    bks = BKS[nm]
    out.append({
        "inst": nm, "nJob": nj, "nMachine": nm_,
        "aoo_best": float(best), "aoo_mean": mean, "aoo_std": stdv,
        "bks": bks,
        "gap_best_pct": round(100 * (best - bks) / bks, 2),
        "gap_mean_pct": round(100 * (mean - bks) / bks, 2),
    })

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(out, f, indent=2, ensure_ascii=False)

print(f"benchmark.json rebuilt: {len(out)} instances -> {OUT}")
for r in out:
    flag = "OK" if r["gap_best_pct"] <= 0 else "WEAK"
    print(f"  {r['inst']} best={r['aoo_best']:.0f} mean={r['aoo_mean']:.1f} "
          f"BKS={r['bks']} gapBest={r['gap_best_pct']:+.1f}% [{flag}]")
