@echo off
REM Stage4 demo: dynamic scenario REAL solve (AOO elite) -> export replay/result JSON
REM -> render 3D digital-twin HTML. Offline (LLM off), zero Key cost.
REM ADDITIVE + safe: default static chain untouched; Python digital-twin render is
REM non-fatal (skipped if python/plotly absent).
taskkill /F /IM matlab.exe >nul 2>&1
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath benchmarks; addpath exports; addpath viz; llmaoo('AOO_DEFAULT_SCENARIO','dynamic','AOO_DEFAULT_PROB','MK01','AOO_DYNAMIC',true,'EXPORT_JSON',true,'SHOW_PLOTS',false,'LLM_ENABLE',false)" -logfile logs\demo_dynamic_full.log -wait
echo EXIT=%ERRORLEVEL%
type logs\demo_dynamic_full.log
echo.
echo Render 3D digital-twin HTML from the latest replay JSON (non-fatal if no python):
powershell -NoProfile -Command "$r = Get-ChildItem -Path logs -Filter replay_2026_*.json | Sort-Object LastWriteTime | Select-Object -Last 1; if ($r) { python viz\digital_twin.py $r.FullName -o figures\demo_dynamic_twin.html } else { Write-Host 'no replay JSON found, skip digital-twin render' }"
echo.
echo Demo outputs:
echo   logs\replay_2026_*.json        (dynamic reschedule frames, baseline = AOO elite)
echo   logs\results_2026_*.json       (solver result, makespan/load/pareto)
echo   figures\demo_dynamic_twin.html (3D digital-twin, optional)
echo.
echo Launch interactive dashboard (static vs dynamic comparison tab):
echo streamlit run viz\dashboard.py
