@echo off
REM Stage-7 submission-grade evidence: full MK01-10 N=30 benchmark + multi-instance SOTA.
REM SAFE: no taskkill; dedicated log. Long run (10x30 solves + 4x30x5 SOTA); run in background.
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath tests; addpath benchmarks; addpath benchmarks/baselines; addpath exports; addpath viz; checkcode('benchmarks/baselines/alns_fjsp.m'); checkcode('tests/stage7_run.m'); stage7_run();" -logfile logs\stage7.log -wait
echo EXIT=%ERRORLEVEL%
type logs\stage7.log
