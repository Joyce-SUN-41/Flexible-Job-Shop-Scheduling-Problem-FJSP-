@echo off
rem Stage1 P0 verify: lightweight re-export (multi scenario, offline, MAXGEN=30 POP=30)
rem Validates new contract: real mk/lb + trimmed obj3 (no Z/mk_n/lb_n) + unified flags.
rem Use cmd /c to call matlab -batch to avoid PowerShell quoting issues.
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz'); addpath('tests'); rng(20260814); res = llmaoo('AOO_DEFAULT_SCENARIO','multi','AOO_THREE_OBJ',true,'EXPORT_JSON',true,'EXPORT_PNG',false,'SHOW_PLOTS',false,'LLM_ENABLE',false,'AOO_MAXGEN',30,'AOO_POP',30); export_result_json(res, fullfile(pwd,'results/tevc_submission/tevc_p0verify_result.json')); disp('P0_VERIFY_DONE');"
