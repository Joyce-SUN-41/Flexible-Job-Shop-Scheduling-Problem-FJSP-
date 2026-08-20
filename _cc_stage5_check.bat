@echo off
REM Stage5 checkcode gate: verify 0 ERROR across all stage-5 touched MATLAB files.
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "check_stage5_errs()" -logfile logs\stage5_checkcode.log -wait
echo EXIT=%ERRORLEVEL%
type logs\stage5_checkcode.log
