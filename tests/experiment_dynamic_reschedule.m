%% experiment_dynamic_reschedule.m — E1 弱实例结构性改进 (实验骨架, 默认关闭)
% 目的: 演示如何在 AOO_DYNAMIC 场景下接入 parse_contract 的 dynamic_strategy/priority 字段，
%       作为事件驱动再调度的策略钩子，探索 MK02/MK06/MK09 等弱实例的结构性改善路径。
%
% 安全/零回归约定 (与 fullchain_demo 一致):
%   - 不修改任何现有 solver 源码；仅在显式调用本函数时运行。
%   - 使用 AOO_DYNAMIC/AOO_THREE_OBJ (Stage8 能力位, 默认 OFF)，不改变默认主链。
%   - 当前 parse_contract 的 dynamic_strategy/priority 字段为"未消费"(见 parse_contract.m L9-13)，
%     本脚本仅读取并 LOG 这些字段, 作为未来主链消费逻辑的钩子演示, 不注入虚假声明。
%   - 输出独立 JSON 到 logs/, 不覆盖任何现有产物。
%
% 用法: tests.experiment_dynamic_reschedule()   (建议 N 小、MAXGEN 低以控时)
function experiment_dynamic_reschedule()
    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports');
    insts = {'MK02','MK06','MK09'};   % 弱实例
    N = 20; MAXGEN = 50;
    rng(20260818);

    rec = struct(); rec.instances = {}; rec.notes = ...
        'dynamic_strategy/priority are RESERVED (parse_contract.m) and NOT consumed by the static main chain; this experiment only logs them as a hook demo for future event-driven reschedule.';
    for i = 1:numel(insts)
        name = insts{i};
        try
            res = llmaoo('AOO_DEFAULT_SCENARIO', 'dynamic', 'AOO_DEFAULT_PROB', name, ...
                         'AOO_DYNAMIC', true, 'AOO_THREE_OBJ', true, ...
                         'MAXGEN', MAXGEN, 'AOO_POP', N, 'LLM_ENABLE', false, ...
                         'EXPORT_JSON', false);
            mk = res.makespan;
            % 演示: 解析 LLM 契约字段 (若为在线路径则有真实值; 离线为默认 REACTIVE/LOAD)
            c = parse_contract('{}');   % 默认契约, 与离线代理一致
            rec.instances{end+1} = struct('inst', name, ...
                                          'dyn_makespan', mk, ...
                                          'dyn_strategy', c.dynamic_strategy, ...
                                          'priority', c.priority, ...
                                          'note', 'AOO_DYNAMIC path ran; contract fields logged (unused by main chain).');
            disp(sprintf('[%s] dynamic mk=%.2f strategy=%s priority=%s', ...
                         name, mk, c.dynamic_strategy, c.priority));
        catch ME
            rec.instances{end+1} = struct('inst', name, 'err', ME.message);
            disp(sprintf('[%s] FAILED: %s', name, ME.message));
        end
    end

    if ~isfolder('logs'), mkdir('logs'); end
    fp = fullfile('logs', 'experiment_dynamic_reschedule.json');
    fid = fopen(fp, 'w');
    if fid >= 0, fwrite(fid, jsonencode(rec, 'PrettyPrint', true), 'char'); fclose(fid); end
    disp(['Wrote ' fp ' (E1 hook demo; reserved fields not consumed by main chain)']);
end
