@echo off
rem Stage3.1 P0: launch tests.stage7_run (offline AOO MK01-10 N=30 benchmark + 5-way SOTA).
rem No network LLM needed; outputs logs/stage7_benchmark.json + logs/stage7_sota.json.
rem Uses -logfile to avoid stale matlab.exe log-lock issues (per project notes).
setlocal
cd /d C:\Users\Joyce_SUN\Desktop\FJSP
if exist "E:\Matlab R2024b\bin\matlab.exe" (
  "E:\Matlab R2024b\bin\matlab.exe" -logfile logs\stage7_run.log -batch "try; addpath('tests'); stage7_run(); catch ME; disp(ME.message); end; exit"
) else (
  echo MATLAB_NOT_FOUND
)
endlocal
