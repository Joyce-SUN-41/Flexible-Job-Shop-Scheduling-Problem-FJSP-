@echo off
REM Stage-7 smoke: quick correctness check (N=3, one instance) for alns + stage7 logic.
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath tests; addpath benchmarks; addpath benchmarks/baselines; addpath exports; addpath viz; checkcode('benchmarks/baselines/alns_fjsp.m'); checkcode('tests/stage7_run.m'); stage7_smoke();" -logfile logs\stage7_smoke.log -wait
echo EXIT=%ERRORLEVEL%
type logs\stage7_smoke.log
