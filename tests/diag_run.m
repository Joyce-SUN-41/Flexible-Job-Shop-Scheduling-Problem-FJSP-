%% 诊断脚本：输出 AOO 真实 makespan/负荷轨迹
cfg = llmaoo_config();
rng(cfg.RNG_SEED);
prob = load_data(cfg.DATA_FILE);
llm_state.levy_gain = 1.0; llm_state.diff_gain = 1.0; llm_state.explore_bias = 1.0;
[elite, aoo] = aoo_engine(prob, cfg, llm_state, []);
[sched, mk, loadVec] = decode(prob, elite);
fprintf('FINAL makespan=%.1f unbal=%.1f\n', mk, max(loadVec)-min(loadVec));
fprintf('trace first20: ');
fprintf('%.3f ', aoo.conv_best(1:min(20,end)));
fprintf('\n');
fprintf('final sum=%.4f iters=%d\n', aoo.conv_best(end), aoo.iters);
fprintf('\n--- 5 runs AOO makespan ---\n');
for r=1:5
    rng(1000+r);
    st.levy_gain=1.0; st.diff_gain=1.0; st.explore_bias=1.0;
    [e2, a2] = aoo_engine(prob, cfg, st, []);
    [~, mk2, lv2] = decode(prob, e2);
    fprintf('run%d: mk=%.1f unbal=%.1f iters=%d\n', r, mk2, max(lv2)-min(lv2), a2.iters);
end
% 随机搜索基线：采样同规模种群取最优
fprintf('\n--- 随机搜索基线 (5 runs, 同评估次数) ---\n');
for r=1:5
    rng(2000+r);
    bestmk = inf; bestunb = inf;
    neval = cfg.AOO_POP * 70;
    for k=1:neval
        X = rand(1, 2*prob.nOp);
        Xos = X(1:prob.nOp); Xms = X(prob.nOp+1:2*prob.nOp);
        [~, order] = sort(Xos, 'descend');
        OS = prob.jobOf(order);
        MS = zeros(1, prob.nOp);
        seen = zeros(1, prob.nJob);
        for t=1:prob.nOp
            j = OS(t); seen(j)=seen(j)+1; kk=seen(j);
            nM = length(prob.op_mach{j}{kk});
            idx = min(max(floor(Xms(t)*nM)+1,1), nM);
            MS(t) = idx;
        end
        chrom = struct('OS',OS,'MS',MS);
        [~, mki, lvi] = decode(prob, chrom);
        if mki < bestmk, bestmk = mki; bestunb = max(lvi)-min(lvi); end
    end
    fprintf('run%d: mk=%.1f unbal=%.1f\n', r, bestmk, bestunb);
end
