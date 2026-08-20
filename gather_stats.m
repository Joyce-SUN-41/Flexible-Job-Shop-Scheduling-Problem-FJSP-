%% gather_stats.m — 阶段5：统计精英解的停滞/负荷特征（独立文件，供 llmaoo / llm_hook 跨文件调用）
% 与 llm_hook.m 内逻辑保持一致。SAFE/ADDITIVE: 阶段三修复阶段二抽离
% llm_hook 时遗留的跨文件不可见问题（局部函数无法被 llmaoo 主入口调用）。
function stats = gather_stats(prob, elite, aoo, cfg, t, stagnation)
    if isempty(elite)
        loadVec = ones(1, prob.nMachine);
        mk = 0; cM = 1;
    else
        [~, mk, loadVec] = decode(prob, elite);
        [~, cM] = max(loadVec);
    end
    stats = struct('gen', t, 'makespan', mk, 'loadVec', loadVec, ...
                   'maxLoadMach', cM, ...
                   'stagWindow', cfg.LLM_CALL_EVERY_GEN, 'stagnation', stagnation);
end
