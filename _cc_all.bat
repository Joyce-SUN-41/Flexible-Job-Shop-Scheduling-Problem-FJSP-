@echo off
REM Full regression suite. SAFE: no taskkill of matlab; dedicated log.
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath tests; addpath benchmarks; addpath benchmarks/baselines; addpath exports; addpath viz; run_all();" -logfile logs\run_all.log -wait
echo EXIT=%ERRORLEVEL%
type logs\run_all.log
