@echo off
setlocal
cd /d C:\Users\Joyce_SUN\Desktop\FJSP
if exist "E:\Matlab R2024b\bin\matlab.exe" (
  "E:\Matlab R2024b\bin\matlab.exe" -logfile logs\ga_test.log -batch "try; addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('tests'); cfg=llmaoo_config(); cfg.AOO_POP=30; cfg.AOO_MAXGEN=20; prob=load_benchmark('MK01'); disp('prob fields ok'); [e,r]=ga_fjsp(prob,cfg); disp(['GA mk=',num2str(r.makespan)]); catch ME; disp('GA_ERROR:'); disp(ME.message); disp(ME.stack); end; exit"
) else (
  echo MATLAB_NOT_FOUND
)
