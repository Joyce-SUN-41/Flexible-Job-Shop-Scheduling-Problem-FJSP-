@echo off
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath('tests'); run_all; exit" -logfile logs\run_all_audit.log
