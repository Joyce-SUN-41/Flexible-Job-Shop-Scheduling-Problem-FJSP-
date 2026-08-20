@echo off
cd /d %~dp0
taskkill /F /IM matlab.exe >nul 2>&1
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath(pwd); run('tests/run_all.m')" -logfile "logs\run_all_stageC.log" -wait
