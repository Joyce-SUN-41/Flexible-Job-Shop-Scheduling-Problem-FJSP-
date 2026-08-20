@echo off
REM 阶段F 单独轻量验证：生成真实 JSON 并实际渲染 Plotly HTML
taskkill /F /IM matlab.exe >nul 2>&1
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath tests; addpath benchmarks; addpath benchmarks/baselines; addpath exports; addpath viz; stageF_run" > logs\stageF_run.log 2>&1
echo EXIT=%ERRORLEVEL%
type logs\stageF_run.log
