@echo off
taskkill /F /IM matlab.exe >nul 2>&1
cd /d %~dp0
"E:\Matlab R2024b\bin\matlab.exe" -batch "addpath tests; addpath benchmarks; addpath exports; addpath viz; files={'llmaoo.m','aoo_engine.m','benchmarks/dynamic_replay.m','exports/export_replay_json.m'}; nErr=0; for k=1:numel(files), m=checkcode(files{k},'-float'); errs=m([m.line]>0 & strcmpi({m.message},'error')); nErr=nErr+numel(errs); for e=1:numel(errs), disp([files{k} ' : ' errs(e).message]); end; end; disp(['checkcode ERROR count = ' num2str(nErr)]); stage1_run();" -logfile logs\stage4_regress.log -wait
echo EXIT=%ERRORLEVEL%
type logs\stage4_regress.log
