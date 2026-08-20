@echo off
REM Stage1 demo: dynamic scenario solve + export replay/results JSON (offline, zero Key cost)
taskkill /F /IM matlab.exe >nul 2>&1
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath benchmarks; addpath exports; addpath viz; llmaoo('AOO_DEFAULT_SCENARIO','dynamic','AOO_DEFAULT_PROB','MK01','AOO_DYNAMIC',true,'EXPORT_JSON',true,'SHOW_PLOTS',false,'LLM_ENABLE',false)" -logfile logs\demo_dynamic.log -wait
echo EXIT=%ERRORLEVEL%
type logs\demo_dynamic.log
echo.
echo Render replay / digital twin HTML with Python:
echo python viz\replay_dynamic.py
echo python viz\digital_twin.py replay_*.json
