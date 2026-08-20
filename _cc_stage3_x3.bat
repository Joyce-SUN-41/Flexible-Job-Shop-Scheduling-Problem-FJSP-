@echo off
REM Stage-3.1 safe augmentation: stronger local search on weak instances MK02/MK06/MK09.
REM Runs offline (LLM_ENABLE=false), writes logs/stage7_strong_x3.json only.
REM Independent log name avoids clashing with leftover matlab.exe holding other logs.
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath tests; addpath benchmarks; addpath benchmarks/baselines; addpath exports; addpath viz; try; stage7_strong_x3; catch ME; disp(getReport(ME)); end; exit" -logfile logs\stage3_x3.log -wait
echo EXIT=%ERRORLEVEL%
type logs\stage3_x3.log
