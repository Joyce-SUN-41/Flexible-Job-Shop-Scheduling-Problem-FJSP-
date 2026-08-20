@echo off
rem Diagnostic: verify MK04 (unequal-ops instance) ga/pso/alns/random baseline variants run
rem without "index exceeds" crash after the prob.opOf fix. (aoo uses aoo_engine directly,
rem not a *_fjsp file, so excluded here.) Quick budget (MAXGEN=20) to validate.
setlocal
cd /d C:\Users\Joyce_SUN\Desktop\FJSP
if exist "E:\Matlab R2024b\bin\matlab.exe" (
  "E:\Matlab R2024b\bin\matlab.exe" -logfile logs\diag_sota_mk04.log -batch "try; addpath('benchmarks'); addpath('benchmarks/baselines'); cfg=llmaoo_config(); cfg.AOO_POP=30; cfg.AOO_MAXGEN=20; prob=load_benchmark('MK04'); disp('MK04 nOpPerJob ok'); for v={'ga','pso','alns','random'}; [e,r]=feval([v{1},'_fjsp'],prob,cfg); disp([v{1},' mk=',num2str(r.makespan)]); end; disp('SOTA_MK04_OK'); catch ME; disp('SOTA_MK04_ERROR:'); disp(ME.message); disp(ME.stack); end; exit"
) else (
  echo MATLAB_NOT_FOUND
)
endlocal
