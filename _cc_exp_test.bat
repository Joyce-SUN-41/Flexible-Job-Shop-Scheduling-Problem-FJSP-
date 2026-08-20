@echo off
setlocal
cd /d C:\Users\Joyce_SUN\Desktop\FJSP
if exist "E:\Matlab R2024b\bin\matlab.exe" (
  "E:\Matlab R2024b\bin\matlab.exe" -logfile logs\exp_test.log -batch "try; addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('tests'); cfg=llmaoo_config(); prob=load_benchmark('MK01'); R=experiment_runs(prob,'N',5,'Variants',{'aoo','ga','pso','alns','random'},'Seed0',9000); disp('EXP OK'); disp(fieldnames(R.mk)); catch ME; disp('EXP_ERROR:'); disp(ME.message); disp(ME.stack); end; exit"
) else (
  echo MATLAB_NOT_FOUND
)
