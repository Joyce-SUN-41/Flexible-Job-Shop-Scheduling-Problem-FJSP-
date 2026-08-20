@echo off
REM 完整回归（绕过被残留进程占用的 run_all_full.log，输出到备用日志）
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath tests; addpath benchmarks; addpath benchmarks/baselines; addpath exports; addpath viz; run_all" > logs\run_all_full2.log 2>&1
echo EXIT=%ERRORLEVEL%
