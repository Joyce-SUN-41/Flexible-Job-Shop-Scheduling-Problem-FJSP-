function llm_gain_quant()
% llm_gain_quant  Stage-D LLM dual-engine gain quantification (online ablation).
% Three arms, same budget + seeds, MK01:
%   (a) pure AOO       : LLM_ENABLE=false (offline constant gains=1.0)
%   (b) offline modul.  : OFFLINE_STRUCTURED_MODULATE=true (structured default, no net)
%   (c) full LLMAOO     : LLM_ENABLE=true + ONLINE_LLM_MODULATE=true (real online LLM)
% Reports mean +/- std makespan per arm; honest attribution via result.llm_counts.

    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz');
    jsonDir = fullfile(pwd, 'logs');
    if ~exist(jsonDir,'dir'), mkdir(jsonDir); end

    N_A = 10;  N_B = 10;  N_C = 8;   % online arm smaller to conserve API quota
    MAXGEN = 60; POP = 40;
    baseSeed = 5000;
    MK = 'data_MK01.mat';   % standard Brandimarte MK01 (10x6x50, BKS=40) for meaningful baseline

    fprintf('=== LLM gain quantification (MK01, MAXGEN=%d POP=%d) ===\n', MAXGEN, POP);

    %% (a) pure AOO (offline constant gains)
    fprintf('[A] pure AOO (LLM_ENABLE=false)\n');
    mkA = zeros(N_A,1);
    for r = 1:N_A
        rng(baseSeed + r);
        res = llmaoo('DATA_FILE', MK, 'LLM_ENABLE', false, 'EXPORT_JSON', false, ...
                     'EXPORT_PNG', false, 'SHOW_PLOTS', false, ...
                     'AOO_MAXGEN', MAXGEN, 'AOO_POP', POP);
        mkA(r) = res.makespan;
    end
    fprintf('  A mean=%.2f std=%.2f\n', mean(mkA), std(mkA));

    %% (b) offline structured modulation (no net)
    fprintf('[B] offline structured modulation\n');
    mkB = zeros(N_B,1);
    for r = 1:N_B
        rng(baseSeed + r);
        res = llmaoo('DATA_FILE', MK, 'LLM_ENABLE', false, 'OFFLINE_STRUCTURED_MODULATE', true, ...
                     'EXPORT_JSON', false, 'EXPORT_PNG', false, 'SHOW_PLOTS', false, ...
                     'AOO_MAXGEN', MAXGEN, 'AOO_POP', POP);
        mkB(r) = res.makespan;
    end
    fprintf('  B mean=%.2f std=%.2f\n', mean(mkB), std(mkB));

    %% (c) full LLMAOO (real online LLM)
    fprintf('[C] full LLMAOO (LLM_ENABLE=true + ONLINE_LLM_MODULATE=true)\n');
    mkC = zeros(N_C,1);
    onlineCalls = 0;
    for r = 1:N_C
        rng(baseSeed + r);
        res = llmaoo('DATA_FILE', MK, 'LLM_ENABLE', true, 'ONLINE_LLM_MODULATE', true, ...
                     'EXPORT_JSON', false, 'EXPORT_PNG', false, 'SHOW_PLOTS', false, ...
                     'AOO_MAXGEN', MAXGEN, 'AOO_POP', POP);
        mkC(r) = res.makespan;
        if isfield(res,'llm_counts'), onlineCalls = onlineCalls + res.llm_counts.llm_online; end
    end
    fprintf('  C mean=%.2f std=%.2f (online LLM calls total=%d)\n', mean(mkC), std(mkC), onlineCalls);

    %% summary + save
    summary = struct();
    summary.N_A = N_A; summary.N_B = N_B; summary.N_C = N_C;
    summary.mkA_mean = mean(mkA); summary.mkA_std = std(mkA);
    summary.mkB_mean = mean(mkB); summary.mkB_std = std(mkB);
    summary.mkC_mean = mean(mkC); summary.mkC_std = std(mkC);
    summary.online_llm_calls = onlineCalls;
    summary.maxtol = 0;
    outPath = fullfile(jsonDir, 'llm_gain_quant.json');
    fid = fopen(outPath, 'w');
    fwrite(fid, jsonencode(summary, 'PrettyPrint', true), 'char');
    fclose(fid);
    fprintf('  saved -> %s\n', outPath);
    fprintf('=== DONE: A=%.2f  B=%.2f  C=%.2f (lower better) ===\n', ...
            mean(mkA), mean(mkB), mean(mkC));
end
