% Stage8 temp verification driver: checkcode + stage8_run (lightweight)
fid = fopen('logs/stage8_result.txt','w');
if fid < 0, error('cannot open result file'); end
fprintf(fid, 'START\n');
try
    addpath('benchmarks'); addpath('tests'); addpath('benchmarks/baselines');
    files = {'llmaoo_config.m','llmaoo.m','evaluate.m','decode.m','parse_contract.m', ...
             'benchmarks/define_problem.m','benchmarks/perturbation.m', ...
             'benchmarks/attach_stage8.m','tests/stage8_run.m','tests/run_all.m'};
    nErr = 0;
    for k=1:numel(files)
        m = checkcode(files{k}, '-float');
        errs = m([m.line]>0 & strcmpi({m.message},'error'));
        if ~isempty(errs)
            nErr = nErr + numel(errs);
            for e=1:numel(errs), fprintf(fid, '  %s : %s\n', files{k}, errs(e).message); end
        end
    end
    fprintf(fid, 'checkcode ERROR count = %d\n', nErr);
    if nErr == 0
        fprintf(fid, 'checkcode OK\n');
        stage8_run();
        fprintf(fid, 'STAGE8_RUN OK\n');
    end
    fprintf(fid, 'DONE\n');
catch ME
    fprintf(fid, 'EXCEPTION: %s\n', ME.message);
    for i=1:numel(ME.stack), fprintf(fid, '  at %s line %d\n', ME.stack(i).name, ME.stack(i).line); end
    fprintf(fid, 'DONE_WITH_ERROR\n');
end
fclose(fid);
