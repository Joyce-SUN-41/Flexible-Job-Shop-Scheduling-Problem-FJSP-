@echo off
rem Stage3 P1 (B): three-objective NSGA-III competitiveness evidence.
rem Runs tests.stageB_sota (default N=30, MK01, POP=30, MAXGEN=60) and writes
rem logs/stageB_sota.json (HV/IGD per-arm + Wilcoxon + Kruskal-Wallis).
rem SAFE: independent log file, no taskkill of any matlab process.
setlocal
cd /d C:\Users\Joyce_SUN\Desktop\FJSP
if exist "E:\Matlab R2024b\bin\matlab.exe" (
  "E:\Matlab R2024b\bin\matlab.exe" -logfile logs\stageB_sota_run.log -batch "try; addpath('tests'); addpath('benchmarks'); addpath('benchmarks/baselines'); stageB_sota(); catch ME; disp(ME.message); end; exit"
) else (
  echo MATLAB_NOT_FOUND
)
endlocal
