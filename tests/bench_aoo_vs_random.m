function bench_aoo_vs_random()
%% 验证：AOO 多次运行稳定性 + 随机基线对比（带进度 flush）
% Wrapped as a function so tests.run_all can call it directly (script-in-function
% static-workspace error otherwise). ADDITIVE: behavior unchanged.
cfg = llmaoo_config();
cfg.AOO_MAXGEN = 120;   % 临时降代速，验证稳定性
rng(cfg.RNG_SEED);
prob = load_data(cfg.DATA_FILE);

fprintf('=== AOO (5 runs, MAXGEN=%d) ===\n', cfg.AOO_MAXGEN);
aooMk = zeros(1,5); aooUnb = zeros(1,5); aooIt = zeros(1,5);
for r = 1:5
    rng(1000 + r);
    st.levy_gain = 1.0; st.diff_gain = 1.0; st.explore_bias = 1.0;
    try
        tic;
        [e2, a2] = aoo_engine(prob, cfg, st, []);
        el = toc;
        [~, mk2, lv2] = decode(prob, e2);
        aooMk(r) = mk2; aooUnb(r) = max(lv2) - min(lv2); aooIt(r) = a2.iters;
        fprintf('run%d: mk=%.1f unbal=%.1f iters=%d (%.1fs)\n', r, mk2, aooUnb(r), a2.iters, el);
    catch ME
        fprintf('run%d ERROR: %s\n', r, ME.message);
    end
    drawnow;
end

fprintf('\n=== 随机搜索基线 (3 runs, 同评估次数=%d) ===\n', cfg.AOO_POP * 70);
randMk = zeros(1,3); randUnb = zeros(1,3);
for r = 1:3
    rng(2000 + r);
    bestmk = inf; bestunb = inf;
    neval = cfg.AOO_POP * 70;
    for k = 1:neval
        X = rand(1, 2*prob.nOp);
        Xos = X(1:prob.nOp); Xms = X(prob.nOp+1:2*prob.nOp);
        [~, order] = sort(Xos, 'descend');
        OS = prob.jobOf(order);
        MS = zeros(1, prob.nOp);
        seen = zeros(1, prob.nJob);
        for t = 1:prob.nOp
            j = OS(t); seen(j) = seen(j)+1; kk = seen(j);
            nM = length(prob.op_mach{j}{kk});
            idx = min(max(floor(Xms(t)*nM)+1, 1), nM);
            MS(t) = idx;
        end
        chrom = struct('OS', OS, 'MS', MS);
        [~, mki, lvi] = decode(prob, chrom);
        if mki < bestmk, bestmk = mki; bestunb = max(lvi) - min(lvi); end
    end
    randMk(r) = bestmk; randUnb(r) = bestunb;
    fprintf('run%d: mk=%.1f unbal=%.1f\n', r, bestmk, bestunb);
end

fprintf('\n=== 汇总 ===\n');
fprintf('AOO   : runs=%d mean mk=%.2f best mk=%.1f mean unbal=%.2f\n', ...
    nnz(aooMk>0), mean(aooMk(aooMk>0)), min(aooMk(aooMk>0)), mean(aooUnb(aooMk>0)));
fprintf('Random: runs=%d mean mk=%.2f best mk=%.1f mean unbal=%.2f\n', ...
    nnz(randMk>0), mean(randMk), min(randMk), mean(randUnb));
end
