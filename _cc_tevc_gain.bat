@echo off
REM _cc_tevc_gain.bat — TEVC 投稿级 LLM 双引擎真实增益量化（联网真实 LLM 版）
REM 难实例 MK04/06/09 + dynamic/multi 场景，三臂消融 aoo/modulate/full，N=30。
cd /d %~dp0
start "" /MIN "E:\Matlab R2024b\bin\matlab.exe" -batch "addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('tests'); tevc_llm_gain; exit" -logfile logs\run_tevc_gain.log
echo Launched tevc_llm_gain (see logs\run_tevc_gain.log)
