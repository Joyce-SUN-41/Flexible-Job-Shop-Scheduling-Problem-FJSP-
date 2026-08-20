@echo off
REM Stage5 P2 (5.1): batch-export convergence traces for std-band aggregation.
REM Runs N independent llmaoo runs (distinct seeds) with EXPORT_CONV_JSON=true,
REM writing logs/conv_*.json. Then viz/plotly_convergence.py aggregates them into
REM a mean+/-std band. SAFE: no taskkill of matlab; dedicated log file.
REM
REM Usage: _cc_conv_batch.bat
REM   (override N/instance via: matlab -batch "stageC_conv_batch(30,'MK01',80)")
set ML=E:\Matlab R2024b\bin\matlab.exe
if not exist "%ML%" (echo no ml & exit /b 2)
cd /d %~dp0
"%ML%" -batch "addpath tests; addpath benchmarks; addpath benchmarks/baselines; addpath exports; stageC_conv_batch(20,'MK01',60);" -logfile logs\conv_batch.log -wait
echo EXIT=%ERRORLEVEL%
type logs\conv_batch.log
