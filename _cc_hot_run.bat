@echo off
REM 跑"最新最火"结果：dynamic 场景 + EXPORT_JSON + 多 run 收敛带 + replay，并渲染全套 Plotly HTML
cd /d %~dp0
if not exist "E:\Matlab R2024b\bin\matlab.exe" (
  echo MATLAB_NOT_FOUND
  exit /b 1
)
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath tests; addpath benchmarks; addpath benchmarks/baselines; addpath exports; addpath viz; hot_run_dynamic" > logs\hot_run.log 2>&1
echo MATLAB_EXIT=%ERRORLEVEL%
type logs\hot_run.log
