@echo off
REM _cc_smoke_tevc.bat — 极小预算 smoke 验证（语法+联网LLM+三目标NSGA-III+EXPORT_JSON）
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz'); r=llmaoo('AOO_DEFAULT_SCENARIO','multi','AOO_THREE_OBJ',true,'EXPORT_JSON',true,'AOO_MAXGEN',5,'AOO_POP',10,'LLM_ENABLE',true,'ONLINE_LLM_MODULATE',true); disp(['SMOKE_OK mk=',num2str(r.makespan)]); if isfield(r,'quality'), disp(['HV=',num2str(r.quality.HV)]); end; if isfield(r,'llm_counts'), disp(['online_calls=',num2str(r.llm_counts.llm_online)]); end; exit" -logfile logs\run_smoke_tevc.log
