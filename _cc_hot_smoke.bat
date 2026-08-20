@echo off
REM 轻量冒烟：验证 dynamic 场景 + EXPORT_JSON 真实跑通并产出 replay JSON（最火"动态+数字孪生"闭环）
cd /d %~dp0
if exist "E:\Matlab R2024b\bin\matlab.exe" (
  "E:\Matlab R2024b\bin\matlab.exe" -batch "addpath tests; addpath benchmarks; addpath benchmarks/baselines; addpath exports; addpath viz; res=llmaoo('AOO_DEFAULT_SCENARIO','dynamic','EXPORT_JSON',true,'EXPORT_PNG',false,'SHOW_PLOTS',false,'AOO_MAXGEN',15,'AOO_POP',30); disp('SMOKE_DONE mk='); disp(res.makespan);" > logs\hot_smoke.log 2>&1
) else (
  echo MATLAB_NOT_FOUND
)
echo EXIT=%ERRORLEVEL%
type logs\hot_smoke.log
