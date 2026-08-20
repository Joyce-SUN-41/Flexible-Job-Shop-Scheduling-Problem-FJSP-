@echo off
REM Stage5 gate batch: runs stage5_run (SOTA compare aoo/ga/pso/random + MK01 bench + full bench scaffold).
REM SAFE: no taskkill of matlab (avoid killing user processes); uses a dedicated log file.
REM Light budget N=10 to avoid suite timeout. Full N=30 evidence via tests.stage5_run manually.
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath tests; addpath benchmarks; addpath benchmarks/baselines; addpath exports; addpath viz; checkcode('tests/stage5_run.m'); checkcode('benchmarks/baselines/pso_fjsp.m'); stage5_run();" -logfile logs\stage5_run.log -wait
echo EXIT=%ERRORLEVEL%
type logs\stage5_run.log
