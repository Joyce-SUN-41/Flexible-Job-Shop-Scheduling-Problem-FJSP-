@echo off
taskkill /F /IM matlab.exe >nul 2>&1
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath benchmarks; addpath exports; addpath viz; r=llmaoo('AOO_DEFAULT_SCENARIO','dynamic','AOO_DEFAULT_PROB','MK01','AOO_POP',8,'AOO_MAXGEN',6,'LLM_ENABLE',false,'EXPORT_JSON',true,'SHOW_PLOTS',false); disp('STAGE4 elite makespan='); disp(r.makespan);" -logfile logs\stage4_verify.log -wait
echo EXIT=%ERRORLEVEL%
type logs\stage4_verify.log
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File _stage4_check.ps1
