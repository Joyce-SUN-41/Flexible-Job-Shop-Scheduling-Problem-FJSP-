@echo off
set ML=E:\Matlab R2024b\bin\matlab.exe
if not exist "%ML%" (echo no ml & exit /b 2)
taskkill /F /IM matlab.exe >nul 2>&1
cd /d %~dp0
"%ML%" -batch "addpath tests; addpath benchmarks; addpath benchmarks/baselines; cc_stage8" -logfile logs\stage8_verify.log -wait
