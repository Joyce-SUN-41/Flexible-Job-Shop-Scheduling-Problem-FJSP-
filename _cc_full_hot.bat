@echo off
REM dynamic + 三目标/绿色/AGV 全最火运行（新窗口后台，独立日志，不杀任何进程）
title FULL_HOT
cd /d %~dp0
if not exist "E:\Matlab R2024b\bin\matlab.exe" ( echo MATLAB_NOT_FOUND & exit /b 1 )
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath tests; addpath benchmarks; addpath benchmarks/baselines; addpath exports; addpath viz; run_full_hot" > logs\full_hot.log 2>&1
echo FULL_EXIT=%ERRORLEVEL%
