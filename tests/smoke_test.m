%% 主链路冒烟测试：llmaoo 完整流程（离线降级）跑通即成功
cfg = llmaoo_config();
fprintf('--- LLMAOO smoke test (MAXGEN=20) ---\n');
rng(cfg.RNG_SEED);
res = llmaoo('MAXGEN', 20);
fprintf('SMOKE_OK makespan=%.1f unbal=%.1f iters=%d\n', res.makespan, res.loadUnb, res.iters);
