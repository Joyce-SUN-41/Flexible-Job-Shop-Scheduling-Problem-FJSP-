@echo off
REM _cc_submit.bat — TEVC 投稿级最火配置一键入口（full 场景 + multi 三目标 + 联网真实 LLM）
REM 固化投稿标准运行方式，不改 llmaoo_config 默认 static（零回归）。
cd /d %~dp0
start "" /MIN "E:\Matlab R2024b\bin\matlab.exe" -batch "addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz'); submit_tevc; exit" -logfile logs\run_submit_tevc.log
echo Launched submit_tevc (see logs\run_submit_tevc.log)
