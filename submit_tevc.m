function submit_tevc()
% submit_tevc  TEVC 投稿级最火配置一键入口（固化投稿标准运行方式，非默认改配置）。
%   目标：把"最火问题设定 + 最火可视化 + 联网真实 LLM"固化为可复现的投稿运行方式，
%   消除"默认静态单目标非最火前沿"的差距，且不破坏 llmaoo_config 默认 static 零回归。
%
%   固化配置（运行时覆盖，不改 llmaoo_config.m 默认值）：
%     - AOO_DEFAULT_SCENARIO='full'  => dynamic + green(energy) + AGV（2026 最火 DFJSP 设定）
%     - AOO_THREE_OBJ=true           => NSGA-III 主选择（aoo_engine L135 真实 NSGA-III）
%     - EXPORT_JSON=true             => 可视化五件套常态产出 JSON
%     - 联网真实 LLM：LLM_ENABLE=true + ONLINE_LLM_MODULATE=true（DEEPSEEK_API_KEY 已备）
%   产出：logs/tevc_full_result.json / tevc_full_replay.json + figures/tevc_*.html
%         logs/tevc_multi_result.json（三目标 NSGA-III 质量指标 HV/IGD 证据）
%
%   零回归：本脚本仅用运行时覆盖参数 + 已有导出/渲染能力，不动 solver 数值语义。

    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz');

    jsonDir = fullfile(pwd, 'logs');
    figDir  = fullfile(pwd, 'figures');
    if ~exist(jsonDir, 'dir'), mkdir(jsonDir); end
    if ~exist(figDir, 'dir'), mkdir(figDir); end

    %% Switch A: full hottest scenario (dynamic + green + AGV, 3-obj NSGA-III, online LLM)
    fprintf('[TEVC-A] full hottest scenario (dynamic+green+AGV, NSGA-III, online LLM)\n');
    rng(20260814);
    res = llmaoo('AOO_DEFAULT_SCENARIO', 'full', ...
                 'AOO_THREE_OBJ', true, ...
                 'EXPORT_JSON', true, 'EXPORT_PNG', false, 'SHOW_PLOTS', false, ...
                 'LLM_ENABLE', true, 'ONLINE_LLM_MODULATE', true, ...
                 'AOO_MAXGEN', 100, 'AOO_POP', 60);
    resPath = fullfile(jsonDir, 'tevc_full_result.json');
    export_result_json(res, resPath);
    fprintf('  mk=%.1f loadUnb=%.1f\n', res.makespan, res.loadUnb);
    if isfield(res, 'quality')
        fprintf('  NSGA-III: HV=%.4f IGD=%.4f PF=%d\n', ...
                res.quality.HV, res.quality.IGD, res.quality.nPF);
    end
    if isfield(res, 'llm_counts')
        fprintf('  LLM online calls=%d (mode online => 真实双引擎增益)\n', res.llm_counts.llm_online);
    end

    %% Replay (real AOO elite baseline + breakdown events) for dynamic digital twin
    cfg = llmaoo_config();
    cfg.AOO_DYNAMIC = true; cfg.AOO_AGV = true; cfg.AOO_THREE_OBJ = true;
    cfg.LLM_ENABLE = true; cfg.ONLINE_LLM_MODULATE = true;
    prob = load_benchmark('MK01');
    prob = attach_stage8(prob, cfg);
    frames = dynamic_replay(prob, cfg, [], res.elite);
    rPath = fullfile(jsonDir, 'tevc_full_replay.json');
    export_replay_json(frames, rPath);
    fprintf('  replay -> %s (%d frames)\n', rPath, numel(frames));

    %% Switch B: multi three-objective NSGA-III (makespan/load/energy) with online LLM
    fprintf('[TEVC-B] multi 3-obj NSGA-III (online LLM)\n');
    rng(20260814);
    resM = llmaoo('AOO_DEFAULT_SCENARIO', 'multi', ...
                  'AOO_THREE_OBJ', true, ...
                  'EXPORT_JSON', true, 'EXPORT_PNG', false, 'SHOW_PLOTS', false, ...
                  'LLM_ENABLE', true, 'ONLINE_LLM_MODULATE', true, ...
                  'AOO_MAXGEN', 100, 'AOO_POP', 60);
    resMPath = fullfile(jsonDir, 'tevc_multi_result.json');
    export_result_json(resM, resMPath);
    fprintf('  mk=%.1f loadUnb=%.1f\n', resM.makespan, resM.loadUnb);
    if isfield(resM, 'quality')
        fprintf('  NSGA-III: HV=%.4f IGD=%.4f PF=%d\n', ...
                resM.quality.HV, resM.quality.IGD, resM.quality.nPF);
    end

    %% Render the full artifact set (non-fatal)
    fprintf('[TEVC] Python Plotly render (non-fatal)\n');
    ganttHtml  = fullfile(figDir, 'tevc_full_gantt.html');
    replayHtml = fullfile(figDir, 'tevc_full_replay.html');
    twinHtml   = fullfile(figDir, 'tevc_full_digital_twin.html');
    cmds = {
        sprintf('python viz/plotly_gantt.py %s -o %s', resPath, ganttHtml);
        sprintf('python viz/replay_dynamic.py %s -o %s', rPath, replayHtml);
        sprintf('python viz/digital_twin.py %s -o %s', resPath, twinHtml);
    };
    pyOk = true;
    for k = 1:numel(cmds)
        [stat, out] = system(cmds{k});
        if stat == 0, fprintf('  [render %d] OK\n', k);
        else, pyOk = false; fprintf('  [render %d] SKIP: %s\n', k, strtrim(out)); end
    end

    %% cleanup stray root json
    stray = dir(fullfile(pwd, 'results_*.json'));
    for s = 1:numel(stray), delete(fullfile(pwd, stray(s).name)); end
    fprintf('submit_tevc DONE (pyOk=%d, full mk=%.1f, multi mk=%.1f)\n', ...
            pyOk, res.makespan, resM.makespan);
end
