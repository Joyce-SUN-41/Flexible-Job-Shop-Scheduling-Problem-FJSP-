@echo off
setlocal
cd /d C:\Users\Joyce_SUN\Desktop\FJSP
if exist "E:\Matlab R2024b\bin\matlab.exe" (
  "E:\Matlab R2024b\bin\matlab.exe" -logfile logs\stage5_validate.log -batch "try; addpath('tests'); addpath('exports'); stage5_validate_check; catch ME; disp(ME.message); end; exit"
) else (
  echo MATLAB_NOT_FOUND
)
