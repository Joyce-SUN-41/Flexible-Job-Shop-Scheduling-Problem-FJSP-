@echo off
REM _cc_runall_tevc.bat — 跑 tests/run_all 零回归（默认 static 主链应 ALL GREEN）
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath('tests'); run_all; exit" -logfile logs\run_all_tevc.log
