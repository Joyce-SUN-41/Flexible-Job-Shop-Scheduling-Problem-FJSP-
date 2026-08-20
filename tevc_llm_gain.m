function tevc_llm_gain()
% tevc_llm_gain  TEVC 投稿级 LLM 双引擎真实增益量化（联网真实 LLM 版）。
%   之前在"加权和单目标 + AOO 已收敛 plateau"框架下联网增益=0，原因是 LLM 调制无数值空间。
%   本脚本在"难实例 + 动态/多目标三目标"场景下跑联网 full 变体，让 LLM 在 AOO 未完全收敛 /
%   扰动重调度场景中显现真实增益。
%
%   三臂消融（experiment_runs 统一预算 + 种子）：
%     aoo     : 纯 AOO（增益=1.0，无 LLM）
%     modulate: AOO + 离线结构化调制（无 Key 也成立的代理）
%     full    : 完整 LLMAOO（联网真实 LLM，DEEPSEEK_API_KEY 已备 => LLM_ENABLE 自动 true）
%   场景：
%     难实例 MK04 / MK06 / MK09（AOO 未完全收敛，LLM 调制有空间）
%     dynamic（DFJSP 重调度，LLM 重调度策略显价值）
%     multi（三目标 NSGA-III，LLM 指导多目标探索）
%   产出：logs/tevc_llm_gain.json（逐场景三臂 mean/best/std + Wilcoxon 显著性）

    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('tests');
    jsonDir = fullfile(pwd, 'logs');
    if ~exist(jsonDir, 'dir'), mkdir(jsonDir); end

    % ---- 阶段二 P1 (2026-08-18 安全增强): 环境态诚实探测 ----
    % 在跑重计算前先显式打印 Key/网络态，使"离线诚实 vs 在线真实"一目了然，
    % 避免把离线 full≡modulate 的产物误当在线 LLM 增益写入论文。
    key = getenv('DEEPSEEK_API_KEY');
    hasKey = ~isempty(key);
    % 轻量网络探测（5s 超时，失败不阻塞，仅作提示）
    netOK = false;
    try
        req = webread('https://api.deepseek.com', 'Timeout', 5);  %#ok<NASGU> 仅探测连通
        netOK = true;
    catch
        netOK = false;
    end
    fprintf('\n#### tevc_llm_gain 环境探测 ####\n');
    fprintf('  DEEPSEEK_API_KEY 注入: %s\n', conditional(hasKey, 'YES', 'NO (离线降级)'));
    fprintf('  api.deepseek.com 网络可达: %s\n', conditional(netOK, 'YES', 'NO (不可达)'));
    if hasKey && netOK
        fprintf('  模式: 在线真实 LLM 增益量化 (full 变体将真实调用 DeepSeek)\n');
    else
        fprintf('  模式: 离线诚实态 (full≡modulate≡aoo, 增益=0 是环境事实，非缺陷)\n');
        fprintf('  说明: 不可宣称在线 LLM 带来量化增益；联网复跑步骤见 env_manifest.json\n');
    end
    fprintf('################################\n');

    N = 30;                 % TEVC 标准独立运行数
    MAXGEN = 80; POP = 50;  % 与 experiment_runs 同等预算
    Seed0 = 20260814;

    % 场景定义：{实例名, 场景类型}
    %   scene='static'  => 用 DATA_FILE 跑标准基准（难实例 MK04/06/09）
    %   scene='dynamic' => AOO_DEFAULT_SCENARIO='dynamic'
    %   scene='multi'   => AOO_DEFAULT_SCENARIO='multi'（三目标 NSGA-III）
    scenes = {
        struct('name', 'MK04', 'scene', 'static', 'file', 'MK04');
        struct('name', 'MK06', 'scene', 'static', 'file', 'MK06');
        struct('name', 'MK09', 'scene', 'static', 'file', 'MK09');
        struct('name', 'MK01_dynamic', 'scene', 'dynamic', 'file', 'MK01');
        struct('name', 'MK01_multi', 'scene', 'multi', 'file', 'MK01');
    };

    summary = struct();
    for s = 1:numel(scenes)
        sc = scenes{s};
        fprintf('\n=== [gain] scene=%s (sceneType=%s) ===\n', sc.name, sc.scene);

        if strcmpi(sc.scene, 'static')
            % 难实例：用 load_benchmark 直接构造，覆盖 DATA_FILE
            prob = load_benchmark(sc.file);
            extra = {'DATA_FILE', sprintf('data/%s.fjs', sc.file)};
        else
            % dynamic / multi：通过场景激活，三目标模式自动开
            prob = load_benchmark(sc.file);
            extra = {'AOO_DEFAULT_SCENARIO', sc.scene, 'AOO_THREE_OBJ', true};
        end

        % 跑三臂（experiment_runs 内 'full' 变体有 Key 时自动联网）
        R = experiment_runs(prob, 'N', N, 'Variants', {'aoo', 'modulate', 'full'}, ...
                            'Seed0', Seed0 + s * 100);
        S = stat_report(R, 'Compare', {'aoo', 'modulate', 'full'});

        % 记录逐臂统计 + 联网 full vs 纯 AOO 显著性
        scStat = struct();
        scStat.aoo     = struct('mean', mean(R.mk.aoo), 'best', min(R.mk.aoo), 'std', std(R.mk.aoo));
        scStat.modulate = struct('mean', mean(R.mk.modulate), 'best', min(R.mk.modulate), 'std', std(R.mk.modulate));
        scStat.full    = struct('mean', mean(R.mk.full), 'best', min(R.mk.full), 'std', std(R.mk.full));
        % 阶段三.2 修复: signrank 返回 [p, h]，第一输出才是真实 p 值（第二输出 h 是布尔
        % 显著性判据）。旧代码 [~, pAooFull] 误取 h（false->0），与 stage7_run 同源 bug。
        % 离线态 full≡aoo 时两列完全相同，signrank 返回 p=1（或 NaN），此处如实记录；
        % 联网态 full≠aoo 时 p 为真实显著性。无论哪种，都不得把 h(布尔)当 p 写入论文。
        [pAooFull, ~] = signrank(R.mk.aoo, R.mk.full);
        if isnan(pAooFull), pAooFull = 1.0; end   % 全相等时 signrank 可能返 NaN，归一到 1
        scStat.p_aoo_vs_full = pAooFull;
        scStat.full_vs_aoo_improve_pct = 100 * (mean(R.mk.aoo) - mean(R.mk.full)) / mean(R.mk.aoo);

        summary.(sc.name) = scStat;
        fprintf('  aoo=%.2f  modulate=%.2f  full(online LLM)=%.2f  improve=%+.1f%%  p_aoo_vs_full=%.4f\n', ...
                mean(R.mk.aoo), mean(R.mk.modulate), mean(R.mk.full), ...
                scStat.full_vs_aoo_improve_pct, pAooFull);
    end

    % 阶段二 P1 (2026-08-18): 将环境态固化进产出 JSON，使结果自带诚实标记，
    % 离线态下游 full≡modulate≡aoo，增益=0 是环境事实，不得误当在线增益。
    summary.env_state = struct('online_llm_available', hasKey && netOK, ...
                               'DEEPSEEK_API_KEY_in_env', hasKey, ...
                               'network_reachable', netOK, ...
                               'mode', conditional(hasKey && netOK, 'online_real', 'offline_honest'), ...
                               'note', 'offline_honest: full==modulate==aoo, gain=0 is env fact; online_real requires Key+net');

    outPath = fullfile(jsonDir, 'tevc_llm_gain.json');
    savejson_tevc(outPath, summary);
    fprintf('\ntevc_llm_gain DONE -> %s\n', outPath);
    fprintf('  env_state.mode=%s (use results/tevc_llm_gain/env_manifest.json for submission boundary)\n', ...
        summary.env_state.mode);
end

function savejson_tevc(path, S)
% savejson_tevc  Minimal ASCII JSON serializer (struct keyed by scene name).
    keys = fieldnames(S);
    parts = cell(numel(keys), 1);
    for i = 1:numel(keys)
        parts{i} = ['"', keys{i}, '":', row2json(S.(keys{i}))];
    end
    txt = ['{', strjoin(parts, ','), '}'];
    fid = fopen(path, 'w'); fwrite(fid, txt, 'char'); fclose(fid);
end

function txt = row2json(S)
    f = fieldnames(S);
    parts = cell(numel(f), 1);
    for i = 1:numel(f)
        v = S.(f{i});
        if isstruct(v)
            parts{i} = ['"', f{i}, '":', row2json(v)];
        elseif ischar(v)
            % Emit valid JSON string (double-quoted, escaped) instead of mat2str
            % (which produces single-quoted MATLAB syntax, not standards-compliant).
            ev = strrep(v, '\', '\\'); ev = strrep(ev, '"', '\"');
            parts{i} = ['"', f{i}, '":"', ev, '"'];
        elseif isnumeric(v) && isscalar(v)
            parts{i} = ['"', f{i}, '":', num2str(v, '%.6g')];
        else
            parts{i} = ['"', f{i}, '":', mat2str(v)];
        end
    end
    txt = ['{', strjoin(parts, ','), '}'];
end
