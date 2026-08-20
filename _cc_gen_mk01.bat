@echo off
cd /d %~dp0
if not exist "E:\Matlab R2024b\bin\matlab.exe" ( echo MATLAB_NOT_FOUND & exit /b 1 )
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath tests; addpath benchmarks; gen_mk01_mat" > logs\mk01_mat.log 2>&1
echo GEN_EXIT=%ERRORLEVEL%
type logs\mk01_mat.log
