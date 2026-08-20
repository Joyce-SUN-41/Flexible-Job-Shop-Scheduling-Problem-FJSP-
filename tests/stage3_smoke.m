function stage3_smoke()
% stage3_smoke  Stage-3 LLM-gain pipeline smoke test (tiny budget, ASCII-only).
%   Verifies: env detection (Key/network), three-arm experiment_runs
%   (aoo/modulate/full), signrank p-value fix, and JSON write path all run
%   cleanly without crash. No solver numerics changed. ADDITIVE: writes only
%   logs/stage3_smoke.json. Honest offline mode (no Key) is expected.

    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('tests');

    % --- env detection (mirrors tevc_llm_gain.m) ---
    key = getenv('DEEPSEEK_API_KEY');
    hasKey = ~isempty(key);
    netOK = false;
    try
        webread('https://api.deepseek.com', 'Timeout', 5); %#ok<NASGU>
        netOK = true;
    catch
        netOK = false;
    end
    fprintf('\n#### stage3_smoke env probe ####\n');
    fprintf('  DEEPSEEK_API_KEY: %s\n', tfstr(hasKey, 'YES', 'NO (offline)'));
    fprintf('  api.deepseek.com reachable: %s\n', tfstr(netOK, 'YES', 'NO'));

    N = 3; MAXGEN = 8; POP = 20;
    prob = load_benchmark('MK04');
    R = experiment_runs(prob, 'N', N, 'Variants', {'aoo', 'modulate', 'full'}, ...
                        'Seed0', 12345, 'Pop', POP, 'MaxGen', MAXGEN);
    S = stat_report(R, 'Compare', {'aoo', 'modulate', 'full'});
    [pAooFull, ~] = signrank(R.mk.aoo, R.mk.full);
    if isnan(pAooFull), pAooFull = 1.0; end
    fprintf('  aoo=%.3f modulate=%.3f full=%.3f p_aoo_vs_full=%.4g\n', ...
            mean(R.mk.aoo), mean(R.mk.modulate), mean(R.mk.full), pAooFull);

    out = struct();
    out.env_state = struct('online_llm_available', hasKey && netOK, ...
                           'DEEPSEEK_API_KEY_in_env', hasKey, ...
                           'network_reachable', netOK, ...
                           'mode', tfstr(hasKey && netOK, 'online_real', 'offline_honest'));
    out.MK04_smoke = struct('aoo_mean', mean(R.mk.aoo), 'modulate_mean', mean(R.mk.modulate), ...
                            'full_mean', mean(R.mk.full), 'p_aoo_vs_full', pAooFull);
    if ~exist('logs', 'dir'), mkdir('logs'); end
    savejson_tevc(fullfile('logs', 'stage3_smoke.json'), out);
    fprintf('stage3_smoke DONE -> logs/stage3_smoke.json\n');
end

function savejson_tevc(path, S)
    keys = fieldnames(S);
    parts = cell(numel(keys), 1);
    for i = 1:numel(keys)
        parts{i} = ['"', keys{i}, '":', row2json(S.(keys{i}))];
    end
    txt = ['{', strjoin(parts, ','), '}'];
    fid = fopen(path, 'w'); fwrite(fid, txt, 'char'); fclose(fid);
end

function s = tfstr(cond, a, b)
    if cond, s = a; else, s = b; end
end

function txt = row2json(S)
    f = fieldnames(S);
    parts = cell(numel(f), 1);
    for i = 1:numel(f)
        v = S.(f{i});
        if isstruct(v)
            parts{i} = ['"', f{i}, '":', row2json(v)];
        elseif ischar(v)
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
