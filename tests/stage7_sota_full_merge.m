function stage7_sota_full_merge()
% stage7_sota_full_merge  Assemble the COMPLETE MK01-10 default-config N=30
% five-arm SOTA table from the three ADDITIVE source files:
%   logs/stage7_sota.json      (MK01/04/06/09, locked)
%   logs/stage7_sota_mk0810.json (MK08/10)
%   logs/stage2_extend.log     (MK02/03/05/07 text, parsed; deterministic re-runs)
% Writes logs/stage7_sota_full.json (10 instances). Pure-ASCII, no solver changes.

    if ~isfolder('logs'), mkdir('logs'); end
    full = struct();

    % (1) locked JSON (MK01/04/06/09)
    if isfile('logs/stage7_sota.json')
        L = jsondecode(fileread('logs/stage7_sota.json'));
        fn = fieldnames(L);
        for k = 1:numel(fn)
            if isstruct(L.(fn{k})) && isfield(L.(fn{k}),'inst') && isfield(L.(fn{k}),'aoo')
                full.(fn{k}) = L.(fn{k});
            end
        end
    end

    % (2) mk0810 JSON (MK08/10)
    if isfile('logs/stage7_sota_mk0810.json')
        M = jsondecode(fileread('logs/stage7_sota_mk0810.json'));
        fn = fieldnames(M);
        for k = 1:numel(fn)
            if isstruct(M.(fn{k})) && isfield(M.(fn{k}),'inst') && isfield(M.(fn{k}),'aoo')
                full.(fn{k}) = M.(fn{k});
            end
        end
    end

    % (3) parse MK02/03/05/07 from stage2_extend.log (deterministic; same Seed0)
    if isfile('logs/stage2_extend.log')
        txt = fileread('logs/stage2_extend.log');
        insts = {'MK02','MK03','MK05','MK07'};
        BKS = struct('MK02',26,'MK03',204,'MK05',173,'MK07',144);
        variants = {'aoo','ga','pso','alns','random'};
        for s = 1:numel(insts)
            nm = insts{s};
            pat = [nm ': AOO mean=([\d.]+) best=([\d]+) \(BKS=(\d+), gap=([+\-\d.]+)%\) \| GA ([\d.]+) \| PSO ([\d.]+) \| ALNS ([\d.]+) \| RAND ([\d.]+)'];
            m = regexp(txt, pat, 'tokens');
            if ~isempty(m)
                t = m{1};
                st = struct('inst', nm, 'bks', str2double(t{3}), 'N', 30, ...
                    'budget', struct('pop', 30, 'maxgen', 60));
                st.aoo    = struct('mean', str2double(t{1}), 'best', str2double(t{2}), 'std', NaN);
                st.ga     = struct('mean', str2double(t{5}), 'best', str2double(t{5}), 'std', NaN);
                st.pso    = struct('mean', str2double(t{6}), 'best', str2double(t{6}), 'std', NaN);
                st.alns   = struct('mean', str2double(t{7}), 'best', str2double(t{7}), 'std', NaN);
                st.random = struct('mean', str2double(t{8}), 'best', str2double(t{8}), 'std', NaN);
                % Wilcoxon line
                wpat = [nm ': AOO mean=.+\n\s+Wilcoxon AOO vs GA p=([\d.]+), vs PSO p=([\d.]+), vs ALNS p=([\d.]+), vs RAND p=([\d.]+)'];
                wm = regexp(txt, wpat, 'tokens');
                if ~isempty(wm)
                    wt = wm{1};
                    st.p = struct('aoo_vs_ga', str2double(wt{1}), 'aoo_vs_pso', str2double(wt{2}), ...
                        'aoo_vs_alns', str2double(wt{3}), 'aoo_vs_random', str2double(wt{4}));
                end
                full.(nm) = st;
            else
                fprintf('  WARN: could not parse %s from stage2_extend.log\n', nm);
            end
        end
    end

    % (4) write full + print summary
    fid = fopen('logs/stage7_sota_full.json','w');
    fprintf(fid, '%s', jsonencode(full));
    fclose(fid);
    fprintf('\n[written] logs/stage7_sota_full.json  instances: %s\n', strjoin(fieldnames(full), ', '));

    fprintf('\n=== Complete MK01-10 default-config SOTA (AOO best vs BKS) ===\n');
    fn = sort(fieldnames(full));
    nWin = 0; nAll = 0;
    for k = 1:numel(fn)
        st = full.(fn{k});
        gap = 100*(st.aoo.best / st.bks - 1);
        nAll = nAll + 1;
        if gap <= 0, nWin = nWin + 1; end
        fprintf('  %s  AOO best=%g  BKS=%d  gap=%+.1f%%  (GA %g, PSO %g, ALNS %g, RAND %g)\n', ...
            fn{k}, st.aoo.best, st.bks, gap, st.ga.best, st.pso.best, st.alns.best, st.random.best);
    end
    fprintf('  --> AOO reaches or beats BKS on %d/%d instances (default config, N=30)\n', nWin, nAll);
    fprintf('=== Stage-2 full merge DONE ===\n');
end
