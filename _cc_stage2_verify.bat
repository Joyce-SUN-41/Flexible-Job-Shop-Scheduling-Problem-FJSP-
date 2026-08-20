@echo off
rem Stage2 P1 verify: light multi-scenario run to confirm energy 3rd-obj now differentiates
rem (was collapsing to 0.6645) and Pareto count is de-duplicated (was 585 inflated).
setlocal
cd /d C:\Users\Joyce_SUN\Desktop\FJSP
if exist "E:\Matlab R2024b\bin\matlab.exe" (
  "E:\Matlab R2024b\bin\matlab.exe" -logfile logs\stage2_verify.log -batch "try; cfg=llmaoo_config(); cfg.AOO_DEFAULT_SCENARIO='multi'; cfg.AOO_MAXGEN=40; cfg.AOO_POP=40; cfg.LLM_ENABLE=false; cfg.EXPORT_JSON=true; res=llmaoo(cfg); o3=res.pareto.obj3; en=o3(:,3); fprintf('PARETO_N=%d EN_UNIQUE=%d EN_MIN=%.4f EN_MAX=%.4f EN_RANGE=%.4f\n', size(o3,1), numel(unique(round(en,6))), min(en), max(en), range(en)); catch ME; disp(ME.message); end; exit"
) else (
  echo MATLAB_NOT_FOUND
)
endlocal
