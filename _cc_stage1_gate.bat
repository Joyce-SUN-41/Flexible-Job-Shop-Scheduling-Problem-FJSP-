@echo off
REM Stage1 gate: verify dynamic + multi scenarios solvable and export JSON (non-fatal Python step)
taskkill /F /IM matlab.exe >nul 2>&1
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath tests; addpath benchmarks; addpath benchmarks/baselines; addpath exports; addpath viz; stage1_run" -logfile logs\stage1_gate.log -wait
echo EXIT=%ERRORLEVEL%
type logs\stage1_gate.log
