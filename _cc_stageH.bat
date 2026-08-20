@echo off
set ML=E:\Matlab R2024b\bin\matlab.exe
if not exist "%ML%" (echo no ml & exit /b 2)
cd /d %~dp0
"%ML%" -batch "addpath tests; addpath benchmarks; addpath benchmarks/baselines; addpath exports; run_all" -logfile logs\run_all_stageH.log -wait
