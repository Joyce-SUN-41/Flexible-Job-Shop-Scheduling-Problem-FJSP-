@echo off
REM Stage2: LLM dual-engine real-gain ablation (online; KEY consumed ONLY here, use sparingly)
REM llmaoo_config already has Key; default LLM_ENABLE=false (zero cost).
REM Here we inject cfg with Cfg param: LLM_CALL_EVERY_GEN=10 (online every 10 gens),
REM LLM_CACHE=true (cache hits cost nothing), DEEPSEEK_MODEL='deepseek-chat' (cheapest).
REM The 'full' variant auto-sets LLM_ENABLE=true when Key present (see experiment_runs.m).
REM SAFE: NO taskkill (avoid killing unrelated matlab). Uses a dedicated log file name.
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath tests; addpath benchmarks; addpath benchmarks/baselines; addpath exports; addpath viz; cfg=llmaoo_config(); cfg.LLM_CALL_EVERY_GEN=10; cfg.LLM_CACHE=false; cfg.DEEPSEEK_MODEL='deepseek-chat'; ablation('MK01','N',10,'Cfg',cfg)" -logfile logs\stage2_ablation.log -wait
echo EXIT=%ERRORLEVEL%
type logs\stage2_ablation.log
