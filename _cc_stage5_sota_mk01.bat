@echo off
setlocal
cd /d C:\Users\Joyce_SUN\Desktop\FJSP
if exist "E:\Matlab R2024b\bin\matlab.exe" (
  "E:\Matlab R2024b\bin\matlab.exe" -logfile logs\stage5_sota_mk04.log -batch "try; addpath('tests'); stage5_sota_full('MK04'); catch ME; disp(ME.message); end; exit"
) else (
  echo MATLAB_NOT_FOUND
)
