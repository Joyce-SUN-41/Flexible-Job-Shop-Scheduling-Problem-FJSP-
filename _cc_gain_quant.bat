@echo off
REM 联网 LLM 增益量化（新窗口后台，独立日志，不杀任何进程）
title LLM_GAIN_QUANT
cd /d %~dp0
if not exist "E:\Matlab R2024b\bin\matlab.exe" ( echo MATLAB_NOT_FOUND & exit /b 1 )
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath tests; addpath benchmarks; addpath benchmarks/baselines; addpath exports; addpath viz; llm_gain_quant" > logs\gain_quant.log 2>&1
echo GAIN_EXIT=%ERRORLEVEL%
