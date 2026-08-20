%% experiment_baseline_moea.m — E2 基线多目标对照 (ADDITIVE, 不改 GA/PSO 源码)
% 目的: 为审稿人可能质疑"GA/PSO 被投影为单点 PF 与 AOO 多点 PF 比 HV 不公平"提供对照实验。
%
% 方法 (诚实口径): 现有 ga_fjsp/pso_fjsp 是加权两目标求解器, 仅返回单点 elite, 不暴露
% 整代非支配前沿。本脚本不改其源码 (零回归), 而是多次独立 run (不同 rng) 收集每次 elite
% 的三目标向量 [mk_n, ld_n, en_n], 聚合为"多起点采样前沿"作为 GA/PSO 覆盖度的近似对照。
% 该口径在输出 JSON 中显式标注为 "multi-start sampling approximation", 不与 AOO 的
% NSGA-III 真 Pareto 前混淆。
%
% 安全/零回归:
%   - 不改 ga_fjsp/pso_fjsp 源码; 仅调用其 (prob, cfg) 接口。
%   - 输出独立 JSON 到 logs/, 不覆盖任何现有产物 (不碰 stageB_sota.json)。
%   - 默认不接入 run_all 门禁。
%
% 用法: tests.experiment_baseline_moea()
function experiment_baseline_moea()
    addpath('benchmarks'); addpath('benchmarks/baselines');
    insts = {'MK01','MK02','MK03','MK04','MK05','MK06','MK07','MK08','MK09','MK10'};
    baselines = {'ga', 'pso'};
    R = 15;                       % 独立 run 数 (多起点采样)
    N = 30; MAXGEN = 50; rng(20260818);

    rec = struct();
    rec.method = 'multi-start sampling approximation (REPLICATE ga/pso elites across R seeds)';
    rec.note = 'GA/PSO are weighted 2-obj solvers returning single elite; this aggregates R independent elites as an approximate front. NOT a native NSGA front. AOO NSGA-III true PF is the reference.';
    rec.R = R; rec.instances = {};

    for i = 1:numel(insts)
        name = insts{i};
        prob = benchmarks.load_benchmark(name);
        % 开启三目标评估路径, 使 evaluate 返回真实归一化 energy_n (零回归: 仅本实验 cfg 生效)
        cfg3 = llmaoo_config(); cfg3.AOO_POP = N; cfg3.AOO_MAXGEN = MAXGEN;
        prob = attach_stage8(prob, cfg3);   % 设定 AOO_THREE_OBJ 等能力位
        instRec = struct('inst', name, 'baselines', struct());
        for bi = 1:numel(baselines)
            bn = baselines{bi};
            pts = zeros(R, 3);     % [mk_n, ld_n, en_n]
            ok = 0;
            for r = 1:R
                rng(1000*r + i*7);
                if strcmp(bn,'ga'), [el, ~] = ga_fjsp(prob, cfg3);
                else, [el, ~] = pso_fjsp(prob, cfg3); end
                [~, mk, ld, ~, ex] = evaluate(prob, el, [1 1 1]);
                % extra.energy_n 已是 [0,1] 归一化 (固定理论界 prob.e_ub); 缺失时回退 NaN
                en_n = ex.energy_n;
                if ~isnan(en_n) && ~isnan(mk) && mk > 0
                    pts(r,:) = [mk / prob.mk_ub, ld / max(prob.mk_ub,1e-9), en_n];
                    ok = ok + 1;
                end
            end
            pts = pts(1:ok, :);     % 有效点
            % 非支配过滤 (构建近似 PF)
            pf = pareto_keep(pts);
            instRec.baselines.(bn) = struct('n_samples', ok, 'approx_front', pf, ...
                'hv_approx', hypervolume(pf), 'note', rec.method);
        end
        rec.instances{end+1} = instRec;
        disp(sprintf('[%s] ga/approx-front=%d pso/approx-front=%d', name, ...
            size(instRec.baselines.ga.approx_front,1), size(instRec.baselines.pso.approx_front,1)));
    end

    if ~isfolder('logs'), mkdir('logs'); end
    fp = fullfile('logs', 'experiment_baseline_moea.json');
    fid = fopen(fp, 'w');
    if fid >= 0, fwrite(fid, jsonencode(rec, 'PrettyPrint', true), 'char'); fclose(fid); end
    disp(['Wrote ' fp ' (E2 multi-start approximation; does NOT modify ga/pso source)']);
end

%% 保留非支配点 (3-obj 最小化)
function pf = pareto_keep(P)
    if isempty(P), pf = zeros(0,3); return; end
    n = size(P,1); keep = true(n,1);
    for i = 1:n
        for j = 1:n
            if i==j, continue; end
            if all(P(j,:) <= P(i,:)) && any(P(j,:) < P(i,:))
                keep(i) = false; break;
            end
        end
    end
    pf = P(keep, :);
end

%% 超体积 (参考点取各维最大值 + 1%，单调变换无关, 仅作相对对比)
function hv = hypervolume(P)
    if isempty(P), hv = 0; return; end
    ref = 1.05 * max(P, [], 1);
    hv = 0;
    for i = 1:size(P,1)
        hv = hv + prod(ref - P(i,:));
    end
end
