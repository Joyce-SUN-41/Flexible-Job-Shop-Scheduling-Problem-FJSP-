function stage7_smoke()
% stage7_smoke  Lightweight correctness smoke for stage7_run (N=3, one instance).
% Validates: alns baseline runs, experiment_runs 'alns' branch works, JSON serializer
% works, and the benchmark loop handles a real MK01. NOT a substitute for the full
% stage7_run (N=30); use _cc_stage7.bat for the real evidence chain.
    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz');
    prob = load_benchmark('MK01');
    R = experiment_runs(prob, 'N', 3, 'Variants', {'aoo','ga','pso','alns','random'}, 'Seed0', 9000);
    ks = fieldnames(R.mk);
    for v = 1:numel(ks)
        fprintf('  %s: mean=%.1f best=%.0f\n', ks{v}, mean(R.mk.(ks{v})), min(R.mk.(ks{v})));
    end
    % exercise the JSON serializer on a tiny struct (no cell field; that path is
    % covered by the real stage7_run.savejson which emits a struct array)
    tiny = struct('inst', 'MK01', 'aoo_best', 34, 'gap_best_pct', -15.0);
    savejson_local('logs/_stage7_smoke.json', tiny);
    fprintf('  smoke JSON -> logs/_stage7_smoke.json\n');
    fprintf('stage7_smoke PASS\n');
end

function savejson_local(path, S)
    f = fieldnames(S);
    parts = cell(numel(f), 1);
    for i = 1:numel(f)
        v = S.(f{i});
        if ischar(v), parts{i} = ['"', f{i}, '":"', v, '"'];
        elseif isnumeric(v) && isscalar(v), parts{i} = ['"', f{i}, '":', num2str(v,'%.6g')];
        else parts{i} = ['"', f{i}, '":', mat2str(v)]; end
    end
    fid = fopen(path, 'w'); fwrite(fid, ['{', strjoin(parts, ','), '}'], 'char'); fclose(fid);
end
