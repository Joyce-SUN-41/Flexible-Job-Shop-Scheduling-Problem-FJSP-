function export_conv_json(result, path)
% export_conv_json  Stage9 (阶段一 P0): per-run convergence trace for std-band aggregation.
%   Writes a minimal JSON carrying ONLY the real makespan convergence trace of one
%   run, so dashboard/plotly_convergence can stack N independent runs into a
%   mean +/- std band. Uses the SAME contract as the primary result: dashboard's
%   make_convergence_figure reads "trace_makespan" first, so this file is directly
%   consumable. Safe: pure serialization; never changes solver numerics.
%
%   NOTE: intentionally a STANDALONE file (not a sub-function of export_result_json)
%   so that llmaoo.m can call it via addpath('exports') under -batch (sub-functions
%   are not visible outside their own file). This is the fix for the
%   "未定义与 'struct' 类型的输入参数相对应的函数 'export_conv_json'" failure.
    if nargin < 2 || isempty(path)
        path = fullfile(pwd, ['conv_' datestr(now,'yyyy_mm_dd_HH_MM_SS') '.json']);
    end
    out = struct();
    out.contract_version = '1.2';
    out.generated = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    out.contract = 'conv_trace';   % 标识：单 run 收敛序列（区别于主结果 results_*）
    if isfield(result, 'trace_makespan') && ~isempty(result.trace_makespan)
        out.trace_makespan = result.trace_makespan(:).';   % 真实 makespan 序列（前端优先）
    elseif isfield(result, 'trace_best') && ~isempty(result.trace_best)
        out.trace_best = result.trace_best(:).';           % 兜底：归一化加权（旧前端兼容）
    end
    if isfield(result, 'seed'), out.seed = result.seed; end
    if isfield(result, 'cfg_hash'), out.cfg_hash = result.cfg_hash; end
    fid = fopen(path, 'w');
    if fid < 0, error('export_conv_json: cannot open %s', path); end
    try
        fwrite(fid, jsonencode(out, 'PrettyPrint', true), 'char');
    catch ME
        fclose(fid); rethrow(ME);
    end
    fclose(fid);
    fprintf('  [Stage9] exported conv JSON -> %s (%d gens)\n', path, numel(out.trace_makespan));
end
