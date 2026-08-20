@echo off
REM Full-chain "hot" closed-loop demo: dynamic + 3-obj solve -> JSON -> Plotly/digital-twin HTML.
REM SAFE: no taskkill of matlab (avoid killing user processes); dedicated log file.
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath tests; addpath benchmarks; addpath benchmarks/baselines; addpath exports; addpath viz; checkcode('tests/fullchain_demo.m'); fullchain_demo();" -logfile logs\fullchain.log -wait
echo EXIT=%ERRORLEVEL%
type logs\fullchain.log
