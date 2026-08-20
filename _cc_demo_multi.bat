@echo off
REM Stage1 demo: multi-objective (3-obj) scenario solve + export results JSON (offline, zero Key cost)
taskkill /F /IM matlab.exe >nul 2>&1
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath benchmarks; addpath exports; addpath viz; llmaoo('AOO_DEFAULT_SCENARIO','multi','AOO_DEFAULT_PROB','MK01','AOO_THREE_OBJ',true,'EXPORT_JSON',true,'SHOW_PLOTS',false,'LLM_ENABLE',false)" -logfile logs\demo_multi.log -wait
echo EXIT=%ERRORLEVEL%
type logs\demo_multi.log
echo.
echo Launch dashboard for 3-obj Pareto scatter:
echo streamlit run viz\dashboard.py
