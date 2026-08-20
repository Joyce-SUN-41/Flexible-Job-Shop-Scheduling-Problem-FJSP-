@echo off
setlocal
cd /d C:\Users\Joyce_SUN\Desktop\FJSP
if exist "E:\Matlab R2024b\bin\matlab.exe" (
  "E:\Matlab R2024b\bin\matlab.exe" -logfile logs\stage3_smoke.log -batch "try; addpath('tests'); stage3_smoke; catch ME; disp(ME.message); end; exit"
) else (
  echo MATLAB_NOT_FOUND
)
