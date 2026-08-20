@echo off
REM Stage C 安全检查：仅 checkcode 新方法，不跑求解
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath('c:\Users\Joyce_SUN\Desktop\FJSP'); addpath('c:\Users\Joyce_SUN\Desktop\FJSP\benchmarks'); cc2=checkcode('aoo_engine.m','-string'); disp('=== aoo_engine ==='); disp(cc2); cc3=checkcode('evaluate.m','-string'); disp('=== evaluate ==='); disp(cc3);"
