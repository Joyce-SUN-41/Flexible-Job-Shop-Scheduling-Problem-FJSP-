@echo off
setlocal
cd /d C:\Users\Joyce_SUN\Desktop\FJSP
if not exist "E:\Matlab R2024b\bin\matlab.exe" (
  echo MATLAB_NOT_FOUND
  exit /b 1
)
set M=E:\Matlab R2024b\bin\matlab.exe
for %%I in (MK01 MK04 MK06 MK09) do (
  echo ===== running %%I =====
  "%M%" -logfile logs\stage5_sota_%%I.log -batch "try; addpath('tests'); stage5_sota_full('%%I'); catch ME; disp(ME.message); end; exit"
)
echo ===== merging =====
"%M%" -logfile logs\stage5_sota_merge.log -batch "try; addpath('tests'); stage5_sota_merge; catch ME; disp(ME.message); end; exit"
echo ALL_DONE
