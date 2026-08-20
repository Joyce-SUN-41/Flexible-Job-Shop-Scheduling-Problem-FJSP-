#!/usr/bin/env python3
"""Stage H - FJSP digital-twin 3D view (Three.js).

Reads a result JSON exported by exports/export_result_json.m (produced by
stage9 / stageF_run), and generates a self-contained HTML file that renders a
rotatable / zoomable 3D shop-floor:
  - X axis = time (0 .. makespan)
  - Y axis = machine (1 .. nMachine)
  - Z axis = visual lane per job (color-coded)
Each operation is a colored box whose length along X equals its duration,
positioned at its machine row and job lane. A sweeping plane animates the
"current processing time" to give the digital-twin feel.

This script is ADDITIVE and read-only over the JSON contract; it never touches
the MATLAB solver, so it cannot regress any numerical result.

Usage:
    python viz/digital_twin.py logs/stageF_result.json -o figures/digital_twin.html
The generated HTML embeds the JSON inline and pulls Three.js from a CDN.
NOTE: the Three.js scene pulls from unpkg (scene hard-codes the unpkg URL), so
an ONLINE connection is required on first load to populate the 3D pane; offline
double-click yields a blank 3D view. The embedded JSON/Gantt still works offline.
"""

import argparse
import html
import json
import os


def load_result(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def build_html(result, src_name):
    # Compatible with both result JSON (problem/schedule) and dynamic-replay JSON
    # (kind=='dynamic_replay', frames:[{time,type,desc,schedule}]).
    # SAFE/ADDITIVE: existing result-JSON path unchanged; replay path is a new branch.
    if result.get("kind") == "dynamic_replay" or "frames" in result:
        return build_html_from_replay(result, src_name)

    prob = result.get("problem", {})
    n_machine = int(prob.get("nMachine", 1))
    n_job = int(prob.get("nJob", 1))
    makespan = float(result.get("makespan", 1.0)) or 1.0
    schedule = result.get("schedule", [])

    # Build operation records [job, op, machine, start, end, dur]
    ops = []
    for row in schedule:
        if not isinstance(row, (list, tuple)) or len(row) < 6:
            continue
        job, op, machine, start, end, dur = (int(row[0]), int(row[1]),
                                             int(row[2]), float(row[3]),
                                             float(row[4]), float(row[5]))
        ops.append({"job": job, "op": op, "machine": machine,
                    "start": start, "end": end, "dur": dur})

    data = {
        "nMachine": n_machine,
        "nJob": n_job,
        "makespan": makespan,
        "ops": ops,
        "src": src_name,
    }
    return _render_page(data)


def build_html_from_replay(result, src_name):
    """Render digital twin from a dynamic-replay JSON (no top-level problem/schedule).
    Infers nMachine/nJob/makespan from the union of all frames' schedule rows."""
    frames = result.get("frames", [])
    ops = []
    n_machine = 1
    n_job = 1
    makespan = 1.0
    for fr in frames:
        sched = fr.get("schedule", [])
        # schedule may be a list of rows [job,op,machine,start,finish,dur]
        rows = sched if isinstance(sched, list) else []
        for row in rows:
            if not isinstance(row, (list, tuple)) or len(row) < 6:
                continue
            job, op, machine, start, finish, dur = (int(row[0]), int(row[1]),
                                                    int(row[2]), float(row[3]),
                                                    float(row[4]), float(row[5]))
            ops.append({"job": job, "op": op, "machine": machine,
                        "start": start, "end": finish, "dur": dur})
            n_machine = max(n_machine, machine)
            n_job = max(n_job, job)
            makespan = max(makespan, finish)
    data = {
        "nMachine": n_machine,
        "nJob": n_job,
        "makespan": makespan,
        "ops": ops,
        "src": src_name + " (dynamic replay)",
    }
    return _render_page(data)


def _render_page(data):
    data_json = json.dumps(data, ensure_ascii=False)
    page = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>FJSP Digital Twin - Stage H</title>
<style>
  body { margin: 0; overflow: hidden; background: #0b1020; color: #e6ecff;
         font-family: -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif; }
  #info { position: fixed; top: 10px; left: 12px; z-index: 10; font-size: 13px;
          line-height: 1.5; text-shadow: 0 1px 2px #000; }
  #info b { color: #7fd1ff; }
  #legend { position: fixed; bottom: 10px; left: 12px; z-index: 10; font-size: 12px; }
  #hud { position: fixed; top: 10px; right: 12px; z-index: 10; font-size: 12px;
         text-align: right; text-shadow: 0 1px 2px #000; }
</style>
</head>
<body>
<div id="info">
  <div><b>FJSP Digital Twin</b> (Stage H)</div>
  <div id="meta">loading...</div>
</div>
<div id="hud">
  <div>drag = rotate &nbsp; scroll = zoom &nbsp; right-drag = pan</div>
  <div id="clock">t = 0</div>
</div>
<div id="legend">Each box = one operation; X = time, Y = machine, color = job.</div>

<script type="importmap">
{
  "imports": {
    "three": "https://unpkg.com/three@0.160.0/build/three.module.js",
    "three/addons/": "https://unpkg.com/three@0.160.0/examples/jsm/"
  }
}
</script>

<script type="module">
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

const DATA = __DATA__;

const nMachine = DATA.nMachine;
const nJob = DATA.nJob;
const makespan = DATA.makespan || 1;
const ops = DATA.ops;

// --- scene ---
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x0b1020);
scene.fog = new THREE.Fog(0x0b1020, 200, 600);

const camera = new THREE.PerspectiveCamera(55, window.innerWidth / window.innerHeight, 0.1, 2000);
// D1: 相机 Z 距离随作业数 Z 跨度自适应，保证多作业实例下整图入镜。
const zSpan = (nJob - 1) * zGap;
camera.position.set(makespan * 0.5, nMachine * 1.5 + 40, zSpan + nMachine * 4 + 120);

const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setPixelRatio(window.devicePixelRatio);
renderer.setSize(window.innerWidth, window.innerHeight);
document.body.appendChild(renderer.domElement);

const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.target.set(makespan * 0.5, nMachine * 0.5, 0);

// --- lights ---
scene.add(new THREE.AmbientLight(0xffffff, 0.55));
const dir = new THREE.DirectionalLight(0xffffff, 0.9);
dir.position.set(60, 120, 80);
scene.add(dir);

// --- axes / floor grid ---
const grid = new THREE.GridHelper(Math.max(makespan, nMachine * 4) * 1.2,
                                  Math.round(Math.max(makespan, nMachine * 4) / 10),
                                  0x335577, 0x223344);
grid.rotation.x = Math.PI / 2;            // lay grid on X-Y plane
grid.position.set(makespan * 0.5, nMachine * 0.5, -8);
scene.add(grid);

// --- color per job ---
function jobColor(j) {
  const hue = (j * 47) % 360;
  return new THREE.Color(`hsl(${hue}, 70%, 58%)`);
}

// --- operation boxes ---
const laneDepth = 6;
const boxGroup = new THREE.Group();
const boxes = [];
let yMax = nMachine;

// D1 修正: Z 轴作业分层间距随实例规模自适应。原固定 laneDepth*1.6(=9.6) 在大作业数下
// 虽不重叠，但 box 深度 d 固定为 4、相机距离未随 Z 跨度缩放，导致多作业实例下视觉拥挤。
// 现令 zGap = max(laneDepth*1.6, d*2.2)，保证任意规模下 box 间间隙恒大于其深度。
const boxDepth = 4;
const zGap = Math.max(laneDepth * 1.6, boxDepth * 2.2);
const zCenter = ((nJob - 1) * zGap) / 2;

ops.forEach((o) => {
  if (o.dur <= 0) return;
  const y = (o.machine - 1) * laneDepth + laneDepth / 2;
  const x = o.start + o.dur / 2;
  // 阶段一 P0: 真实作业泳道分层（修复原 `* 0.0` 笔误）。D1: 用自适应 zGap 并相对
  // zCenter 居中，避免大 nJob 时 Z 跨度偏移导致相机取景失衡。
  const z = ((o.job - 1) % Math.max(nJob, 1)) * zGap - zCenter;
  const w = Math.max(o.dur, 0.4);
  const h = laneDepth * 0.7;
  const d = boxDepth;
  const geo = new THREE.BoxGeometry(w, h, d);
  const mat = new THREE.MeshStandardMaterial({
    color: jobColor(o.job), roughness: 0.45, metalness: 0.15,
    transparent: true, opacity: 0.92,
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.position.set(x, y, z);
  mesh.userData = o;
  boxGroup.add(mesh);
  boxes.push(mesh);
});
scene.add(boxGroup);

// machine labels (sprites)
function makeLabel(text, x, y, z) {
  const c = document.createElement('canvas');
  c.width = 128; c.height = 40;
  const ctx = c.getContext('2d');
  ctx.fillStyle = '#9fd6ff'; ctx.font = 'bold 28px sans-serif';
  ctx.fillText(text, 6, 30);
  const tex = new THREE.CanvasTexture(c);
  const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, transparent: true }));
  sp.scale.set(18, 6, 1);
  sp.position.set(x, y, z);
  return sp;
}
for (let m = 1; m <= nMachine; m++) {
  scene.add(makeLabel('M' + m, -10, (m - 1) * laneDepth + laneDepth / 2, 0));
}

// --- sweeping time plane (digital-twin animation) ---
const planeGeo = new THREE.PlaneGeometry(2, nMachine * laneDepth + 4);
const planeMat = new THREE.MeshBasicMaterial({ color: 0x66e0ff, transparent: true, opacity: 0.25, side: THREE.DoubleSide });
const sweep = new THREE.Mesh(planeGeo, planeMat);
sweep.rotation.y = Math.PI / 2;
sweep.position.set(0, nMachine * laneDepth / 2, 0);
scene.add(sweep);

// --- HUD ---
document.getElementById('meta').innerHTML =
  `jobs=<b>${nJob}</b> machines=<b>${nMachine}</b> ops=<b>${ops.length}</b> makespan=<b>${makespan.toFixed(1)}</b><br>src: ${html.escape(DATA.src)}`;
const clockEl = document.getElementById('clock');

// --- animate ---
const clock = new THREE.Clock();
let t = 0;
function animate() {
  requestAnimationFrame(animate);
  const dt = clock.getDelta();
  t = (t + dt * makespan * 0.12) % (makespan + 20);
  sweep.position.x = t;
  // highlight in-progress ops
  boxes.forEach(b => {
    const o = b.userData;
    const active = (t >= o.start && t <= o.end);
    b.material.emissive = new THREE.Color(active ? 0x335577 : 0x000000);
    b.material.opacity = active ? 1.0 : 0.85;
  });
  clockEl.textContent = 't = ' + t.toFixed(1);
  controls.update();
  renderer.render(scene, camera);
}
animate();

window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
});
</script>
</body>
</html>
"""
    page = page.replace("__DATA__", data_json)
    # html.escape is not needed for JSON inside <script>; ensure no </script> break
    page = page.replace("</script>", "<\\/script>")
    return page


def main():
    ap = argparse.ArgumentParser(description="Generate FJSP 3D digital-twin HTML from a result JSON.")
    ap.add_argument("result", help="path to results_*.json")
    ap.add_argument("-o", "--output", default=None, help="output HTML path")
    args = ap.parse_args()

    result = load_result(args.result)
    src_name = os.path.basename(args.result)
    out = args.output or os.path.join("figures", "digital_twin.html")
    page = build_html(result, src_name)
    with open(out, "w", encoding="utf-8") as f:
        f.write(page)
    # Report actual rendered dimensions inferred from the JSON payload (works for
    # both result JSON and dynamic-replay JSON).
    import re as _re
    _m = _re.search(r'const DATA = (\{.*?\});', page, _re.S)
    if _m:
        _d = json.loads(_m.group(1))
        print(f"[digital_twin] wrote {out} (jobs={_d.get('nJob')}, "
              f"machines={_d.get('nMachine')}, ops={len(_d.get('ops', []))}, "
              f"makespan={_d.get('makespan')})")
    else:
        print(f"[digital_twin] wrote {out}")


if __name__ == "__main__":
    main()
