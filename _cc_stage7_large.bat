@echo off
rem Stage1 P0 (B): large-config compensation for weak instances MK02/MK06/MK09.
rem Runs tests.stage7_large_config (N=30, budget scales with nOp) and writes
rem logs/stage7_large.json (independent of default-config primary evidence).
rem SAFE: independent log file, no taskkill of any matlab process.
setlocal
cd /d C:\Users\Joyce_SUN\Desktop\FJSP
if exist "E:\Matlab R2024b\bin\matlab.exe" (
  "E:\Matlab R2024b\bin\matlab.exe" -logfile logs\stage7_large_run.log -batch "try; addpath('tests'); addpath('benchmarks'); addpath('benchmarks/baselines'); stage7_large_config(); catch ME; disp(ME.message); end; exit"
) else (
  echo MATLAB_NOT_FOUND
)
endlocal
