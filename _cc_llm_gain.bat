@echo off
setlocal
cd /d C:\Users\Joyce_SUN\Desktop\FJSP

REM 阶段二 P1: 联网 LLM 真实增益量化 (tevc_llm_gain)
REM 安全声明: 本脚本默认离线诚实态 (full==modulate==aoo, 增益=0 是环境事实)。
REM 若要真实联网增益, 请在下方 set DEEPSEEK_API_KEY= 处填入真实 Key, 且确保网络可达,
REM 然后运行本脚本。未填 Key 时脚本仍会跑, 但自动降级为离线诚实态 (不伪造增益)。

REM === 用户填写真实 Key 后取消下一行注释 ===
REM set DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxx

if exist "E:\Matlab R2024b\bin\matlab.exe" (
  "E:\Matlab R2024b\bin\matlab.exe" -logfile logs\llm_gain.log -batch "try; addpath('tests'); tevc_llm_gain; catch ME; disp(ME.message); end; exit"
) else (
  echo MATLAB_NOT_FOUND
)
