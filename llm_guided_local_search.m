%% LLM 指导的关键块局部搜索（替代通用随机 vns）
% 输入 elite 个体 + LLM 给出的 ls_mode/target_machine；
% 通过 decode 反推真实关键路径（makespan 决定链），在关键机器上的连续同机工序块做邻域。
function [chrom, obj] = llm_guided_local_search(prob, chrom, cfg, contract)
    [sched, makespan, ~] = decode(prob, chrom);
    if makespan <= 0, chrom = chrom; obj = obj_of(prob,chrom,cfg); return; end

    % ---- 反推真实关键路径：从 makespan 机器上末工序回溯 ----
    [critPath, critMach] = critical_path(prob, sched, makespan);

    % LLM 可指定目标机器（关键块所在机器）；否则用反推出的关键机器
    if contract.target_machine >= 1 && contract.target_machine <= prob.nMachine
        critMach = contract.target_machine;
    end

    % 关键机器上的工序（按时间排序），从中抽取连续同机块作为关键块
    % 阶段4：复用 critical_block_neighborhood 统一关键块邻域入口
    [onM, ~] = critical_block_neighborhood(prob, sched, critMach);
    if isempty(onM), chrom = chrom; obj = obj_of(prob,chrom,cfg); return; end

    best = chrom; bestObj = obj_of(prob, chrom, cfg);
    K = cfg.LS_KMAX;
    % 修复(2026-08-15)：LLM 显式要求不做局部搜索时，直接保留精英（避免违背意图的无谓扰动）
    if strcmpi(contract.ls_mode, 'NONE')
        chrom = best; obj = bestObj; return;
    end
    for k = 1:K
        cand = best;
        if strcmpi(contract.ls_mode, 'MACHINE_REASSIGN')
            % 邻域：把关键路径上某工序改派到其可选机器中工时更短者（负荷均衡）
            if ~isempty(critPath)
                e = critPath(randi(numel(critPath)));
                tt = loc_of(sched, e);                 % 正确定位：sched 全局序号
                j = cand.OS(tt);
                % 关键修复(2026-08-15)：tt 是 OS 位置，当前排列下该位置的工件内工序号
                % 必须用 sched(tt).op，不能用固定映射 prob.opOf(tt)（后者对应初始 jobOf
                % 顺序，与进化后的 OS 排列可能不一致，会在不等工序实例上越界/错位）。
                kk = sched(tt).op;                     % 当前 OS 位置 tt 的真实工序号
                machSet = prob.op_mach{j}{kk};
                timeSet = prob.op_time{j}{kk};
                if length(machSet) > 1
                    [~, ti] = min(timeSet);            % 选最快可选机器
                    cand.MS(tt) = ti;
                end
            end
        else
            % CRITICAL_BLOCK 默认：交换关键机器上两工序的机器（若可行）
            if numel(onM) >= 2
                a = randperm(numel(onM), 2);
                ta = loc_of(sched, onM(a(1)));
                tb = loc_of(sched, onM(a(2)));
                tmp = cand.MS(ta); cand.MS(ta) = cand.MS(tb); cand.MS(tb) = tmp;
            end
        end
        o = obj_of(prob, cand, cfg);
        if sum(o) < sum(bestObj)
            best = cand; bestObj = o;
        end
    end
    chrom = best; obj = bestObj;
end
