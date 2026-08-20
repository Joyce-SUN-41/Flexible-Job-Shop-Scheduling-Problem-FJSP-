@echo off
rem Stage3.1 [7.2]-only re-run: regenerate logs/stage7_sota.json with corrected budget
rem (30x60, matching [7.1]) and correct Wilcoxon p-values (signrank [p,h] -> p).
rem Uses an independent log file to avoid clashing with any stale matlab process.
setlocal
cd /d C:\Users\Joyce_SUN\Desktop\FJSP
if exist "E:\Matlab R2024b\bin\matlab.exe" (
  "E:\Matlab R2024b\bin\matlab.exe" -logfile logs\stage7_sota_rerun.log -batch "try; addpath('tests'); stage7_sota_only(); catch ME; disp(ME.message); end; exit"
) else (
  echo MATLAB_NOT_FOUND
)
endlocal
