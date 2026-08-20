%% 反推关键路径（makespan 决定链）
% 从 makespan 机器上结束时刻 == makespan 的工序出发，沿"前驱完工==本工序开始"
% 的关系回溯；同时返回该关键路径所在的关键机器号。
function [cp, critMach] = critical_path(prob, sched, makespan)
    nOp = numel(sched);
    % 阶段3：边界防御——空调度（单工序退化或异常）直接返回空路径并标记 critMach=-1，
    % 调用方（refine_elite）据此 return，避免对空 sched 索引崩溃。
    if nOp == 0 || ~isfinite(makespan) || makespan <= 0
        cp = []; critMach = -1; return;
    end
    idxMap = zeros(prob.nJob, max(prob.nOpPerJob));
    for t = 1:nOp
        idxMap(sched(t).job, sched(t).op) = t;
    end
    % 找 makespan 末工序：结束时间 == makespan 的工序
    % 阶段3：做严格相等（以机器 finish 落在 makespan 末尾）后，允许极小容差，
    % 并统一按 finish 取最大值以稳定处理"多末工序并列"情形（取其一即可，关键机器仍有效）。
    enders = find(abs([sched.finish] - makespan) < 1e-9);
    if isempty(enders)
        % 退化为取 finish 最大的工序（兜底，避免数据浮点误差导致整链丢失）
        [~, mi] = max([sched.finish]);
        enders = mi;
    end
    [~, mi] = max([sched(enders).finish]);
    start_e = enders(mi);
    critMach = sched(start_e).machine;

    cp = [];
    cur = start_e;
    while cur > 0
        cp = [cur, cp];   %#ok<AGROW>
        s = sched(cur);
        prevJobOp = idxMap(s.job, max(1, s.op-1));
        prevMachine = -1;
        onSameMach = find([sched.machine] == s.machine);
        cand = onSameMach([sched(onSameMach).finish] <= s.start + 1e-9);
        if ~isempty(cand)
            [~, cj] = max([sched(cand).finish]);
            prevMachine = cand(cj);
        end
        if prevMachine > 0 && prevMachine ~= cur
            cur = prevMachine;
        elseif s.op > 1 && prevJobOp > 0
            cur = prevJobOp;
        else
            cur = -1;
        end
    end
end
