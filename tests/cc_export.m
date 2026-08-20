% Stage9 temp verification driver: checkcode + stage9_run (lightweight, no full solve)
fid = fopen('logs/stage9_result.txt','w');
if fid < 0, error('cannot open result file'); end
fprintf(fid, 'START\n');
try
    addpath('benchmarks'); addpath('tests'); addpath('benchmarks/baselines'); addpath('exports');
    files = {'llmaoo.m','llmaoo_config.m','exports/export_result_json.m','tests/stage9_run.m', ...
             'tests/run_all.m'};
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
        stage9_run();
        fprintf(fid, 'STAGE9_RUN OK\n');
    end
    fprintf(fid, 'DONE\n');
catch ME
    fprintf(fid, 'EXCEPTION: %s\n', ME.message);
    for i=1:numel(ME.stack), fprintf(fid, '  at %s line %d\n', ME.stack(i).name, ME.stack(i).line); end
    fprintf(fid, 'DONE_WITH_ERROR\n');
end
fclose(fid);
