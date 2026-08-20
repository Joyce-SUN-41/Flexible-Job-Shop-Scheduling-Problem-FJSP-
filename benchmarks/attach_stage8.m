function prob = attach_stage8(prob, cfg)
% attach_stage8 safely augments a load_data-style prob with Stage8 capability
% fields. Safety: only appends has_energy/energy/ENERGY_UB/has_agv/agv_time/
% agv_capacity; never changes fields decode/aoo_engine depend on (nJob/nOp/
% op_mach/op_time/mk_ub ...). Capability fields are constructed only when the
% corresponding cfg switch is true; default all-false => identical to original
% prob (zero regression).
%
% Field sources (load_data style): prob.op_mach{j}{k} (candidate machine set),
% prob.op_time{j}{k} (durations), prob.machine_weight (machine weight vector),
% prob.nMachine.

    if cfg.AOO_THREE_OBJ
        % 兼容 define_problem('multi') 已构造 energy 的场景：若 has_energy 已真，
        % 保留既有 energy 字段，不重复构造（避免被 else 重置为 false）。
        if ~isfield(prob,'energy') || ~prob.has_energy
            NJ = prob.nJob; NM = prob.nMachine;
            energy = cell(NJ,1);
            for j=1:NJ
                nOpj = prob.nOpPerJob(j);
                Ek = cell(nOpj,1);
                for k=1:nOpj
                    machSet = prob.op_mach{j}{k};
                    timeSet = prob.op_time{j}{k};
                    Em = zeros(1,NM);
                    for qi=1:length(machSet)
                        m = machSet(qi);
                        if m>=1 && m<=NM
                            Em(m) = timeSet(qi) * prob.machW(m);
                        end
                    end
                    Ek{k} = Em;
                end
                energy{j} = Ek;
            end
            prob.energy = energy;
        end
        prob.has_energy = true;   % 三目标开启：强制置真（与 define_problem 一致）
        if cfg.ENERGY_UB > 0, prob.ENERGY_UB = cfg.ENERGY_UB; end
    else
        prob.has_energy = false;
    end

    if cfg.AOO_AGV && ~isfield(prob,'agv_time')
        NM = prob.nMachine;
        agv = zeros(NM,NM);
        for a=1:NM
            for b=1:NM
                agv(a,b) = abs(a-b) * 0.5;
            end
        end
        prob.agv_time = agv;
        prob.agv_capacity = 1;
        prob.has_agv = true;
    else
        prob.has_agv = false;
    end

    % 单一权威标志位（阶段一 P0）：以 cfg 开关为唯一来源，统一设置
    % prob.AOO_DYNAMIC / prob.AOO_AGV，并同步遗留的 has_dynamic/has_agv
    % 字段，消除 attach_stage8 不设 has_dynamic（仅 define_problem 设）导致的
    % 三处标志位（cfg.AOO_DYNAMIC / prob.AOO_DYNAMIC / prob.has_dynamic）语义
    % 分裂、前端/导出误判动态场景的问题。
    prob.AOO_DYNAMIC   = cfg.AOO_DYNAMIC;
    prob.AOO_AGV       = cfg.AOO_AGV;
    prob.AOO_THREE_OBJ = cfg.AOO_THREE_OBJ;   % 阶段四 P2: 统一权威标志位（quality_metrics/stage8_run 读 prob.AOO_THREE_OBJ 判定三目标）
    prob.has_dynamic   = cfg.AOO_DYNAMIC;   % 同步遗留字段，保持一致
    % has_agv 已在上方 AGV 分支据 cfg.AOO_AGV 设置；此处确保统一（无 AGV 时显式 false）
    if ~cfg.AOO_AGV, prob.has_agv = false; end
end
