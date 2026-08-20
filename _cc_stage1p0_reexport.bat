@echo off
rem Stage1 P0 re-export: run submit_tevc to refresh TEVC submission artifacts.
rem Output lands in logs/tevc_full_result.json + logs/tevc_multi_result.json; copy to
rem results/tevc_submission/ to replace the 2026-08-14 normalized legacy files.
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz'); addpath('tests'); submit_tevc();"
copy /Y logs\tevc_full_result.json results\tevc_submission\tevc_full_result.json
copy /Y logs\tevc_multi_result.json results\tevc_submission\tevc_multi_result.json
echo STAGE1P0_REEXPORT_DONE
