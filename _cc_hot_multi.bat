@echo off
REM 补跑：multi 三目标 FJSP + NSGA-III 质量指标 (HV/IGD)，产出 Pareto + 三目标散点到 logs/hot_multi*.json
cd /d %~dp0
if not exist "E:\Matlab R2024b\bin\matlab.exe" ( echo MATLAB_NOT_FOUND & exit /b 1 )
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath tests; addpath benchmarks; addpath benchmarks/baselines; addpath exports; addpath viz; hot_run_multi" > logs\hot_multi.log 2>&1
echo MATLAB_EXIT=%ERRORLEVEL%
type logs\hot_multi.log
