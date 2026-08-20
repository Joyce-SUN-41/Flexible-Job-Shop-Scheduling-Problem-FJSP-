@echo off
rem C1: loadUnb normalization sensitivity analysis (ADDITIVE, zero-regression).
rem Runs tests.analyze_loadunb_norm and writes logs/loadunb_sensitivity.json.
rem SAFE: independent log file, no taskkill of any matlab process. Does NOT modify evaluate.m.
setlocal
cd /d C:\Users\Joyce_SUN\Desktop\FJSP
if exist "E:\Matlab R2024b\bin\matlab.exe" (
  "E:\Matlab R2024b\bin\matlab.exe" -logfile logs\loadunb_sensitivity_run.log -batch "try; addpath('tests'); addpath('benchmarks'); addpath('benchmarks/baselines'); analyze_loadunb_norm(); catch ME; disp(ME.message); end; exit"
) else (
  echo MATLAB_NOT_FOUND
)
endlocal
