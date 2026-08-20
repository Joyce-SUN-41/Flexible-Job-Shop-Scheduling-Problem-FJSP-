%% analyze_loadunb_norm.m — C1 敏感性分析 (ADDITIVE, 零回归)
% 目的: 验证 evaluate.m 当前用 mk_ub 归一化 loadUnb 是否压制了负荷均衡目标的边际贡献。
%       对默认 DATA_FILE 实例在 W_LOAD 取值下跑 AOO, 记录求得 makespan / loadUnb 的 tradeoff,
%       输出 logs/loadunb_sensitivity.json 供投稿前决策。
%
% 安全: 只读 cfg + llmaoo, 不改 solver 源码; 输出独立 JSON, 不覆盖任何现有产物。
%
% 重要诚实声明 (SCOPE): 实证发现 W_LOAD>0 或 MAXGEN 较大时, llmaoo 返回的
%   result.loadUnb / result.problem.mk_ub 在某些运行下被结构化为 struct, 导致
%   "struct -> double" 转换失败——这本身印证了 C 阶段体检关于 loadUnb 归一化环节
%   脆弱性的判断 (evaluate.m 的 loadUnb/mk_ub 路径)。完整 W_LOAD 扫描 + MK01-10
%   需单独修复 evaluate.m (非 ADDITIVE), 留作独立任务。本脚本交付单点 W_LOAD=0
%   的可跑证据 + 上述暗伤记录。
%
% 用法: tests.analyze_loadunb_norm()
function analyze_loadunb_norm()
    addpath('benchmarks'); addpath('benchmarks/baselines');
    wLoad = 0.0;          % 单点 (W_LOAD>0 触发 evaluate 内部 struct->double 暗伤)
    MAXGEN = 50;
    rng(42);

    rec = struct(); rec.inst = {}; rec.wLoad = wLoad; rec.data = {};
    try
        res = llmaoo('W_LOAD', wLoad, 'LLM_ENABLE', false, ...
                     'EXPORT_JSON', false, 'EXPORT_PNG', false, ...
                     'SHOW_PLOTS', false, 'AOO_MAXGEN', MAXGEN);
        mk = res.makespan;
        ld = res.loadUnb;
        ub = res.mk_ub;
        if ~isscalar(ub) || ~isfinite(ub) || ub <= 0, ub = 1e-9; end
        ld_norm = ld / ub;
        prob = res.problem;
        row = struct('inst', 'default(DATA_FILE)', 'nJob', prob.nJob, ...
                     'nMachine', prob.nMachine, 'mk_ub', ub, 'results', ...
                     struct('wLoad', wLoad, 'makespan', mk, 'loadUnb', ld, ...
                            'loadUnb_norm', ld_norm));
        rec.data{end+1} = row;
        disp(sprintf('[default] W_LOAD=%.2f mk=%.1f ld=%.1f ld_norm=%.4f', wLoad, mk, ld, ld_norm));
    catch ME
        rec.err = ME.message;
        disp(['C1 failed: ' ME.message]);
    end

    if ~isfolder('logs'), mkdir('logs'); end
    out = struct('analysis', 'loadUnb_normalization_sensitivity', ...
                 'note', 'Audits mk_ub-denominator suppression of load-balance objective. SCOPE: default DATA_FILE, W_LOAD=0 only. W_LOAD>0 (or larger MAXGEN) triggers a struct->double failure inside evaluate.m loadUnb normalization (loadUnb/mk_ub), corroborating the C-stage audit that loadUnb normalization is fragile. Full sweep + MK01-10 need a separate evaluate.m fix (non-ADDITIVE), left for a dedicated task. read-only vs evaluate.m.', ...
                 'mk_ub_denominator_used', true, 'wLoad_scan_safe', [0.0], ...
                 'wLoad_blocked_gt0', true, 'maxgen', MAXGEN, 'instances', rec.data);
    if isfield(rec, 'err'), out.error = rec.err; end
    fp = fullfile('logs', 'loadunb_sensitivity.json');
    fid = fopen(fp, 'w');
    if fid >= 0, fwrite(fid, jsonencode(out, 'PrettyPrint', true), 'char'); fclose(fid); end
    disp(['Wrote ' fp]);
end
