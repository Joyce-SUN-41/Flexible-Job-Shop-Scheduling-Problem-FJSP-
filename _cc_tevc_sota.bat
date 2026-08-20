@echo off
REM _cc_tevc_sota.bat — TEVC 投稿级完整 MK01-10 + 七方 SOTA 对比（含联网 full 变体）
REM N=30，覆盖 aoo/modulate/full/ga/pso/alns/random，产出 logs/tevc_benchmark.json + tevc_sota.json
cd /d %~dp0
start "" /MIN "E:\Matlab R2024b\bin\matlab.exe" -batch "addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('tests'); addpath('exports'); addpath('viz'); tevc_sota; exit" -logfile logs\run_tevc_sota.log
echo Launched tevc_sota (see logs\run_tevc_sota.log)
