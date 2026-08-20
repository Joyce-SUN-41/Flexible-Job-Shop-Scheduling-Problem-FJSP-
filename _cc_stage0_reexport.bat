@echo off
rem Stage-0 safety re-export: regenerate results/tevc_submission/* with current fixed code.
rem OFFLINE (LLM_ENABLE=false): no network, no claimed online LLM gain, honest re-export.
rem Uses an independent log file to avoid clashing with any stale matlab process.
setlocal
cd /d C:\Users\Joyce_SUN\Desktop\FJSP
if exist "E:\Matlab R2024b\bin\matlab.exe" (
  "E:\Matlab R2024b\bin\matlab.exe" -logfile logs\stage0_reexport.log -batch "try; addpath('exports'); submit_tevc_offline(); catch ME; disp(ME.message); end; exit"
) else (
  echo MATLAB_NOT_FOUND
)
endlocal
