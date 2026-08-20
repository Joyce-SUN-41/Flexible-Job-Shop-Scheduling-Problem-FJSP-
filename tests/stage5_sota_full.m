function stage5_sota_full(varargin)
% stage5_sota_full  Complete Stage-5 SOTA comparison per improvement_plan B3:
%   4 representative instances (MK01/04/06/09) x 5 arms (aoo/ga/pso/alns/random)
%   x N=30, EQUAL budget (POP=30, MAXGEN=60, matching stage7_sota), with
%   Wilcoxon significance (stat_report).
%   Process-isolated usage (robust against long-session memory stalls):
%     stage5_sota_full('MK01')           % one instance -> logs/stage5_sota_MK01.json
%     stage5_sota_full('MK04')           % ... MK04 ...
%     stage5_sota_merge                   % merge all stage5_sota_MKxx.json -> stage5_sota_compare.json
% SAFE / ADDITIVE: only calls public entry points. Does NOT modify solver numerics.

    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('tests');
    logDir = fullfile(pwd, 'logs');
    if ~exist(logDir, 'dir'), mkdir(logDir); end

    if nargin >= 1 && ischar(varargin{1}) && strcmpi(varargin{1}, 'merge')
        stage5_sota_merge();
        return;
    end

    if nargin >= 1 && ischar(varargin{1}) && ~isempty(varargin{1})
        insts = {varargin{1}};
    else
        insts = {'MK01', 'MK04', 'MK06', 'MK09'};
    end
    variants = {'aoo', 'ga', 'pso', 'alns', 'random'};
    N = 30; Pop = 30; MaxGen = 60;

    alldata = struct();
    for ii = 1:numel(insts)
        nm = insts{ii};
        fprintf('\n==== [SOTA] instance %s (N=%d, %d arms) ====\n', nm, N, numel(variants));
        p = load_benchmark(nm);
        R = experiment_runs(p, 'N', N, 'Variants', variants, 'Seed0', 1001 + ii*100, ...
                            'Pop', Pop, 'MaxGen', MaxGen);
        S = stat_report(R, 'Compare', {'aoo', 'ga', 'pso', 'alns', 'random'});
        rec = struct();
        rec.inst = nm;
        rec.N = N;
        rec.budget = sprintf('POP=%d MAXGEN=%d', Pop, MaxGen);
        rec.mk = struct();
        rec.lb = struct();
        fns = fieldnames(R.mk);
        for k = 1:numel(fns)
            v = fns{k};
            rec.mk.(v) = R.mk.(v);
            rec.lb.(v) = R.lb.(v);
        end
        rec.wilcoxon = struct();
        tfns = fieldnames(S.test);
        for k = 1:numel(tfns)
            tn = tfns{k};
            tt = S.test.(tn);
            rec.wilcoxon.(tn) = struct('p', tt.p, 'significant', tt.significant, ...
                                       'mean_improve_pct', tt.mean_improve_pct);
        end
        alldata.(nm) = rec;
        fprintf('  aoo best=%.1f  ga=%.1f  pso=%.1f  alns=%.1f  random=%.1f\n', ...
                min(R.mk.aoo), min(R.mk.ga), min(R.mk.pso), min(R.mk.alns), min(R.mk.random));
    end

    out = struct();
    out.instances = insts;
    out.variants = variants;
    out.N = N;
    out.budget = sprintf('POP=%d MAXGEN=%d', Pop, MaxGen);
    out.data = alldata;

    % Single-instance run writes its own file (no clobber); merge assembles full JSON.
    if numel(insts) == 1
        cmpPath = fullfile(logDir, ['stage5_sota_' insts{1} '.json']);
    else
        cmpPath = fullfile(logDir, 'stage5_sota_compare.json');
    end
    try
        str = jsonencode(out);
        fid = fopen(cmpPath, 'w', 'n', 'UTF-8');
        fwrite(fid, str, 'char');
        fclose(fid);
        if numel(insts) == 1
            fprintf('\nSOTA instance %s saved: %s (run stage5_sota_merge to assemble)\n', insts{1}, cmpPath);
        else
            fprintf('\nSOTA comparison (full B3) saved: %s\n', cmpPath);
        end
    catch ME
        fprintf('  [warn] could not write %s: %s\n', cmpPath, ME.message);
    end
    fprintf('stage5_sota_full DONE\n');
end

