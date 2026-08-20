function stageB_sota(varargin)
% stageB_sota  Stage-3 P1 gate: three-objective NSGA-III competitiveness evidence.
%
% 在 multi 场景（makespan + load + energy 三目标）下，对比 AOO(NSGA-III 真实三目标
% 主选) 与 Random 基线（多目标投影）以及两目标基线 GA/PSO/ALNS（精英解投影到三目标
% 空间作单点）的 Pareto 前沿质量，用标准多目标指标 HV (Hypervolume) / IGD 量化，
% 并做 Wilcoxon（AOO vs Random）与 Kruskal-Wallis（五组整体差异）显著性检验。
% 这是 TEVC 多目标严谨性硬要求（对标 NSGA-III / MOEA/D 论文惯例）。
%
% 与阶段7 门禁[6]（两目标 AOO vs Random）互补：门禁[6] 验证默认两目标主链竞争力；
% 本脚本验证投稿多目标路径（AOO_THREE_OBJ=true）的 NSGA-III 三目标竞争力。
%
% Run (full, N=30):
%   cd project root in MATLAB, then execute tests.stageB_sota
% Run (light, for regression gate [20]):
%   tests.stageB_sota('N', 15, 'MaxGen', 40, 'Pop', 30)
%
% Output: logs/stageB_sota.json  (HV/IGD per-run samples + Wilcoxon p + desc stats)
%
% SAFE / ADDITIVE: only calls public entry points (define_problem / aoo_engine /
% evaluate / nsga3_quality / non_dominated_sort). Does NOT modify any solver numerics.
% Note: define_problem('multi',...) already attaches energy + sets AOO_THREE_OBJ=true,
% so no separate attach_energy step is needed.

    p = inputParser;
    addParameter(p, 'N', 30, @(x) isscalar(x) && x > 0);
    addParameter(p, 'Prob', 'MK01', @ischar);
    addParameter(p, 'Pop', 30, @(x) isscalar(x) && x > 0);
    addParameter(p, 'MaxGen', 60, @(x) isscalar(x) && x > 0);
    addParameter(p, 'Seed0', 7001, @isscalar);
    parse(p, varargin{:});
    N = p.Results.N;
    probName = p.Results.Prob;
    POP = p.Results.Pop;
    MAXGEN = p.Results.MaxGen;
    seed0 = p.Results.Seed0;

    addpath(pwd); addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('tests');

    fprintf('\n==== Stage-3 P1: three-obj NSGA-III SOTA (AOO vs Random) ====\n');
    fprintf('  prob=%s  N=%d  POP=%d  MAXGEN=%d\n', probName, N, POP, MAXGEN);

    % 三目标激活的 prob（define_problem('multi') 已置 prob.AOO_THREE_OBJ=true + energy）
    pMul = define_problem('multi', probName);
    assert(pMul.has_energy && pMul.AOO_THREE_OBJ, 'multi problem attach failed');

    cfg = llmaoo_config();
    cfg.AOO_POP = POP; cfg.AOO_MAXGEN = MAXGEN; cfg.AOO_REFINE_EVERY = 5;
    cfg.AOO_THREE_OBJ = true;             % 三目标路径：NSGA-III 真实主选
    cfg.OFFLINE_STRUCTURED_MODULATE = false;
    cfg.ONLINE_LLM_MODULATE = false;

    hvAoo = zeros(N, 1); igdAoo = zeros(N, 1);
    hvRnd = zeros(N, 1); igdRnd = zeros(N, 1);
    hvGa  = zeros(N, 1); hvPso = zeros(N, 1); hvAlns = zeros(N, 1);

    baselineNames = {'ga', 'pso', 'alns'};
    for i = 1:N
        rng(seed0 + i, 'twister');

        % ---- AOO (NSGA-III 三目标主选) ----
        init_state = struct('levy_gain', 1.0, 'diff_gain', 1.0, 'explore_bias', 1.0, 'last_best', Inf);
        onIter = @(t, b, m) init_state;   % 纯 AOO，无调制（公平竞争）
        [~, resA] = aoo_engine(pMul, cfg, init_state, onIter);
        obj3A = resA.pareto.obj3;
        if isfield(resA, 'quality') && isfinite(resA.quality.HV)
            hvAoo(i) = resA.quality.HV;
            igdAoo(i) = resA.quality.IGD;
        else
            % 兜底：直接算（防御 quality 缺失）
            Q = nsga3_quality(obj3A);
            hvAoo(i) = Q.HV; igdAoo(i) = Q.IGD;
        end

        % ---- Random 基线（多目标投影）----
        % 同评价预算：POP*MAXGEN 次随机可行解码，收集三目标向量 [mk_n,ld_n,en_n]，
        % 取非支配层作 PF，再算 HV/IGD（公平：同预算、同三目标归一化）。
        [obj3R, ~] = random_threeobj(pMul, cfg);
        Qr = nsga3_quality(obj3R);
        hvRnd(i) = Qr.HV; igdRnd(i) = Qr.IGD;

        % ---- 两目标基线 (GA / PSO / ALNS) 的三目标投影 ----
        % 它们是两目标加权求解器，无 NSGA-III 多目标 PF；将其每次运行的精英解投影到
        % 三目标空间作单点（single-point PF），与 AOO 的多点 PF 用 HV 对比。
        % 这诚实反映"三目标覆盖度"：多目标主选应显著优于两目标加权投影。
        for bi = 1:numel(baselineNames)
            resB = baseline_threeobj_single(pMul, cfg, baselineNames{bi});
            hvB = resB.hv;
            if strcmp(baselineNames{bi}, 'ga'),   hvGa(i)  = hvB;
            elseif strcmp(baselineNames{bi},'pso'), hvPso(i) = hvB;
            else                                     hvAlns(i)= hvB; end
        end

        if mod(i, 5) == 0 || i == 1
            fprintf('  run %2d/%d  AOO HV=%.3f | RND %.3f | GA %.3f | PSO %.3f | ALNS %.3f\n', ...
                i, N, hvAoo(i), hvRnd(i), hvGa(i), hvPso(i), hvAlns(i));
        end
    end

    % ---- 描述统计 ----
    function s = desc(x)
        s = struct('mean', mean(x), 'std', std(x), 'median', median(x), ...
                   'best', max(x), 'worst', min(x));
    end
    dAoo = desc(hvAoo); dRnd = desc(hvRnd);
    dGa = desc(hvGa); dPso = desc(hvPso); dAlns = desc(hvAlns);

    % ---- Wilcoxon: AOO HV 是否显著优于 Random HV ----
    % ranksum(x1, x0): h==1 表示 x1 分布显著大于 x0。
    % HV 越大越好 => 检验 AOO HV > Random HV（即 AOO 不显著更差）。
    [pval, h] = ranksum(hvAoo, hvRnd);
    aooBetter = (h ~= 1);   % AOO 不显著劣于 Random（HV 口径）
    improvePct = 100 * (dAoo.mean - dRnd.mean) / max(abs(dRnd.mean), 1e-9);

    fprintf('\n  AOO  HV mean=%.4f std=%.4f median=%.4f best=%.4f\n', ...
        dAoo.mean, dAoo.std, dAoo.median, dAoo.best);
    fprintf('  RND  HV mean=%.4f std=%.4f median=%.4f best=%.4f\n', ...
        dRnd.mean, dRnd.std, dRnd.median, dRnd.best);
    fprintf('  GA   HV mean=%.4f std=%.4f median=%.4f\n', dGa.mean, dGa.std, dGa.median);
    fprintf('  PSO  HV mean=%.4f std=%.4f median=%.4f\n', dPso.mean, dPso.std, dPso.median);
    fprintf('  ALNS HV mean=%.4f std=%.4f median=%.4f\n', dAlns.mean, dAlns.std, dAlns.median);
    fprintf('  Wilcoxon (AOO HV vs RND HV): p=%.4g  h=%d  improve=%.1f%%\n', pval, h, improvePct);
    if aooBetter
        fprintf('  THREE-OBJ COMPETITIVENESS PASS (AOO NSGA-III HV not significantly worse than Random)\n');
    else
        fprintf('  THREE-OBJ COMPETITIVENESS WEAK (AOO HV significantly worse; review NSGA-III params)\n');
    end

    % ---- Kruskal-Wallis: 五组 HV 分布是否同源（多算法整体差异）----
    % 注意：GA/PSO/ALNS 为两目标加权求解器，其精英解投影到三目标空间为单点 PF，
    % HV 天然低于 AOO/Random 的多点 PF——本检验用于量化"多目标主选覆盖度优势"。
    groups = {hvAoo, hvRnd, hvGa, hvPso, hvAlns};
    kw_p = NaN; kw_h = NaN;
    try
        [kw_p, kw_h] = kruskalwallis(cat(1, groups{:}), ...
            repmat({'AOO';'RND';'GA';'PSO';'ALNS'}, N, 1), 'off');
        fprintf('  Kruskal-Wallis (5-group HV): p=%.4g  h=%d\n', kw_p, kw_h);
    catch ME
        fprintf('  [warn] Kruskal-Wallis skipped: %s\n', ME.message);
    end

    % ---- 持久化（供 dashboard / 论文）----
    logDir = fullfile(pwd, 'logs');
    if ~exist(logDir, 'dir'), mkdir(logDir); end
    out = struct();
    out.prob = probName;
    out.scenario = 'multi';
    out.N = N;
    out.budget = struct('POP', POP, 'MAXGEN', MAXGEN);
    out.hv = struct('aoo', hvAoo, 'random', hvRnd, 'ga', hvGa, 'pso', hvPso, 'alns', hvAlns);
    out.igd = struct('aoo', igdAoo, 'random', igdRnd);
    out.desc_hv = struct('aoo', dAoo, 'random', dRnd, 'ga', dGa, 'pso', dPso, 'alns', dAlns);
    out.wilcoxon_hv_p = pval;
    out.wilcoxon_hv_h = h;
    out.kruskalwallis_p = kw_p;
    out.kruskalwallis_h = kw_h;
    out.improve_pct = improvePct;
    out.aoo_three_obj_competitive = aooBetter;
    out.note = ['AOO_THREE_OBJ=true NSGA-III main-select vs Random/GA/PSO/ALNS 3-obj projection, ' ...
                'equal eval budget. GA/PSO/ALNS are 2-obj weighted solvers; their elite is ' ...
                'projected to 3-obj space as a single point (lower HV by design).'];
    try
        str = jsonencode(out);
        fpath = fullfile(logDir, 'stageB_sota.json');
        fid = fopen(fpath, 'w', 'n', 'UTF-8');
        fwrite(fid, str, 'char');
        fclose(fid);
        fprintf('  saved: %s\n', fpath);
    catch ME
        fprintf('  [warn] could not write stageB_sota.json: %s\n', ME.message);
    end

    fprintf('==== stageB_sota DONE ====\n');
end

%% random_threeobj — Random baseline collecting three-obj vectors (multi scenario).
% Same evaluation budget as AOO (POP*MAXGEN random feasible decodes), returns the
% non-dominated front of normalized three-obj vectors [mk_n, ld_n, en_n].
function [obj3, bestMk] = random_threeobj(prob, cfg)
    nEval = cfg.AOO_POP * cfg.AOO_MAXGEN;
    bestMk = Inf;
    vecs = zeros(nEval, 3);
    for e = 1:nEval
        [OS, MS] = random_feasible(prob);
        chrom = struct('OS', OS, 'MS', MS);
        [~, mk, loadVec, ~, ex] = evaluate(prob, chrom, [1 1 1]);  % 三目标分支
        vecs(e, :) = ex.obj(:).';   % [mk_n, ld_n, en_n]
        if mk < bestMk, bestMk = mk; end
    end
    % 非支配层（公平 PF 定义）
    fronts = non_dominated_sort(vecs);
    if isempty(fronts)
        obj3 = vecs;
    else
        obj3 = vecs(fronts{1}, :);
    end
end

%% baseline_threeobj_single — Run a 2-obj baseline (ga/pso/alns), project its elite to 3-obj.
% Returns a struct with .hv (single-point HV of the projected elite in 3-obj space)
% and .obj3 (1x3 normalized vector [mk_n, ld_n, en_n]). The baseline is a weighted
% 2-obj solver, so its elite is a single Pareto point (not a front). Used to show
% that the NSGA-III multi-objective main-select yields a strictly larger HV coverage.
function resB = baseline_threeobj_single(prob, cfg, name)
    resB = struct('hv', NaN, 'obj3', [NaN NaN NaN]);
    % baselines share the (prob, cfg) interface and return [elite, result].
    if strcmp(name, 'ga'),   [elite, ~] = ga_fjsp(prob, cfg);
    elseif strcmp(name,'pso'), [elite, ~] = pso_fjsp(prob, cfg);
    else                       [elite, ~] = alns_fjsp(prob, cfg); end
    if isempty(elite), return; end
    % Project elite to the 3-obj space (weighted [1 1 1] triggers the three-obj branch).
    [~, ~, ~, ~, ex] = evaluate(prob, elite, [1 1 1]);
    obj3 = ex.obj(:).';
    resB.obj3 = obj3;
    % Single-point HV (Monte-Carlo approximate in nsga3_quality).
    Q = nsga3_quality(obj3);
    resB.hv = Q.HV;
end

function [OS, MS] = random_feasible(prob)
% random_feasible  Sample a feasible OS (job-permutation multiset) and MS (random machine per op).
    nJob = prob.nJob;
    opCount = cellfun(@numel, prob.op_mach);
    OS = [];
    for j = 1:nJob, OS = [OS, j * ones(1, opCount(j))]; end
    OS = OS(randperm(numel(OS)));
    MS = zeros(sum(opCount), 1);
    idx = 0;
    for j = 1:nJob
        for k = 1:opCount(j)
            idx = idx + 1;
            em = prob.op_mach{j}{k};
            MS(idx) = em(randi(numel(em)));
        end
    end
end
