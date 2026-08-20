function prob = define_problem(mode, src, varargin)
% define_problem unified problem definition for Stage8:
%   static  -> base FJSP (backward compatible with load_benchmark)
%   green   -> + energy objective (has_energy=true)
%   transport -> + AGV transport (has_agv=true)
%   multi   -> three objectives: makespan + load + energy
%   dynamic -> dynamic rescheduling scenario (breakdown/urgent/delay)
%   full    -> dynamic + green + transport
% Safety: never mutates base fields; new fields default-absent => main chain unaffected.

    p = inputParser;
    addParameter(p,'scenario','breakdown',@ischar);
    addParameter(p,'agvCapacity',1,@(x)isscalar(x)&&x>0);
    parse(p,varargin{:});
    scenario = p.Results.scenario;
    agvCap = p.Results.agvCapacity;

    if strcmpi(src,'MK01')
        base = load_benchmark('MK01');
    else
        try
            base = load_benchmark(src);
        catch
            error('define_problem: unknown instance "%s"', src);
        end
    end

    prob = base;
    prob.mode = mode;
    prob.has_energy = false;
    prob.has_agv    = false;
    prob.has_dynamic= false;
    prob.dynamic_scenario = '';

    modeU = lower(mode);
    full = strcmpi(modeU,'full');

    if strcmp(modeU,'green') || strcmp(modeU,'multi') || full
        prob = attach_energy(prob);
    end
    if strcmp(modeU,'transport') || full
        prob = attach_agv(prob, agvCap);
    end
    if strcmp(modeU,'dynamic') || full
        prob.has_dynamic = true;
        prob.dynamic_scenario = scenario;
    end
end

function prob = attach_energy(prob)
    NJ = prob.nJob;
    NM = prob.nMachine;
    energy = cell(NJ,1);
    e_ub = 0;   % 阶段二 P1: 能耗固定理论上界 = 每工序选最大能耗机器之和（与 mk_ub 同构）
    for j=1:NJ
        NJop = prob.nOpPerJob(j);
        Ek = cell(NJop,1);
        for k=1:NJop
            Em = zeros(1,NM);
            for m=1:NM
                tm = prob.op_time{j}{k}(m);
                w  = prob.machW(m);
                Em(m) = tm * w;
            end
            Ek{k} = Em;
            e_ub = e_ub + max(Em);   % 累加该工序最大可能能耗
        end
        energy{j} = Ek;
    end
    prob.energy = energy;
    prob.e_ub = e_ub;              % 固定上界，供 evaluate 归一化 energy（修复 en 塌缩到 0.667 渐近线）
    prob.has_energy = true;
    prob.AOO_THREE_OBJ = true;   % 多目标激活标志（与 attach_stage8 语义一致，供 build_pareto/quality 判断）
end

function prob = attach_agv(prob, cap)
    NM = prob.nMachine;
    agv = zeros(NM,NM);
    for a=1:NM
        for b=1:NM
            agv(a,b) = abs(a-b) * 0.5;
        end
    end
    prob.agv_time = agv;
    prob.agv_capacity = cap;
    prob.has_agv = true;
end
