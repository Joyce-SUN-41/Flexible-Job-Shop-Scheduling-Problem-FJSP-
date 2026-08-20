@echo off
REM Targeted robustness test (gate [18]): unequal-ops aoo_engine + parse_fjs dual layout.
REM SAFE: no taskkill; dedicated log.
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath tests; addpath benchmarks; addpath benchmarks/baselines; addpath exports; checkcode('tests/stage_robustness_test.m'); checkcode('tests/run_all.m'); stage_robustness_test();" -logfile logs\robust.log -wait
echo EXIT=%ERRORLEVEL%
type logs\robust.log
