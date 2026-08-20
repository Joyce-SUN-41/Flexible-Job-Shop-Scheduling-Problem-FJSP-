%% load_data.m — 载入并校验 FJSP 实例数据
% 返回结构体 prob，集中封装问题实例，供各模块统一访问。
% 兼容原 data.mat（operation_time / operation_machine / num_machine /
% machine_weight / num_job / num_op）。

function prob = load_data(filename)
    if nargin < 1, filename = 'data.mat'; end

    % --- 数据文件存在性校验（改进7） ---
    if ~exist(filename, 'file')
        error('load_data:FileNotFound', ...
              '未找到数据文件 "%s"。请确认 data.mat 位于工作目录，或在 config.DATA_FILE 中指定正确路径。', filename);
    end

    % --- 必需字段校验（改进7：友好报错而非裸 load 崩溃） ---
    required = {'operation_time', 'operation_machine', 'num_machine', ...
                'num_job', 'num_op'};
    raw = load(filename);                 % 先整体载入，再按字段校验
    present  = fieldnames(raw);
    missing  = setdiff(required, present);
    if ~isempty(missing)
        error('load_data:MissingField', ...
              '数据文件 "%s" 缺少必需字段：%s。\n请检查数据文件格式（需含 operation_time / operation_machine / num_machine / num_job / num_op）。', ...
              filename, strjoin(missing, ', '));
    end
    s = raw;
    prob.op_time   = s.operation_time;   % {job}{op} -> 各可选机器工时向量
    prob.op_mach   = s.operation_machine;% {job}{op} -> 各可选机器编号向量
    prob.nMachine  = s.num_machine;
    if isfield(s, 'machine_weight') && ~isempty(s.machine_weight)
        prob.machW = s.machine_weight;   % 机器权重（可选使用）
    else
        prob.machW = ones(1, s.num_machine);
    end
    prob.nJob      = s.num_job;
    prob.nOpPerJob = s.num_op(:)';        % 行向量，每工件的工序数
    prob.nOp       = sum(prob.nOpPerJob); % 总工序数

    % 阶段3：operation_time / operation_machine 必须为两层 cell
    %   {job}{op} -> 向量，否则 decode 会在 {} 索引处崩溃（静默错误传播）。
    if ~iscell(s.operation_time) || ~iscell(s.operation_machine)
        error('load_data:BadStructure', ...
              'operation_time / operation_machine 必须是两层 cell（{job}{op}），收到非 cell 结构。');
    end
    if length(s.operation_time) ~= prob.nJob || length(s.operation_machine) ~= prob.nJob
        error('load_data:BadStructure', ...
              'operation_time / operation_machine 的 job 层数(%d/%d) 必须等于 num_job(%d)', ...
              length(s.operation_time), length(s.operation_machine), prob.nJob);
    end

    % 构建全局工序索引映射
    %   opGlobal(job, k) = 该工序的全局序号 t
    %   jobOf(t) / opOf(t) = 全局序号 t 对应的工件号 / 工序序号
    % 便于编码阶段由染色体位置反查 (job, op)
    idx = 0;
    opGlobal = zeros(prob.nJob, max(prob.nOpPerJob));
    jobOf = zeros(1, prob.nOp);
    opOf  = zeros(1, prob.nOp);
    for j = 1:prob.nJob
        for k = 1:prob.nOpPerJob(j)
            idx = idx + 1;
            opGlobal(j, k) = idx;
            jobOf(idx) = j;
            opOf(idx)  = k;
        end
    end
    prob.opGlobal   = opGlobal;
    prob.jobOf      = jobOf;
    prob.opOf       = opOf;

    % 工件工序计数校验
    assert(length(prob.op_time) == prob.nJob, 'operation_time 与 num_job 不匹配');
    assert(length(prob.op_mach) == prob.nJob, 'operation_machine 与 num_job 不匹配');
    for j = 1:prob.nJob
        assert(length(prob.op_time{j}) == prob.nOpPerJob(j), ...
            sprintf('工件 %d 的 operation_time 工序数与 num_op 不一致', j));
        assert(length(prob.op_mach{j}) == prob.nOpPerJob(j), ...
            sprintf('工件 %d 的 operation_machine 工序数与 num_op 不一致', j));
        % 机器编号合法性：op_mach 中每个编号必须落在 [1, nMachine] 整数区间
        for k = 1:prob.nOpPerJob(j)
            mj = prob.op_mach{j}{k};
            assert(all(mj >= 1 & mj <= prob.nMachine & mj == round(mj)), ...
                sprintf('工件 %d 工序 %d 的 operation_machine 含非法机器编号（须为 1..%d 的整数）', ...
                        j, k, prob.nMachine));
            assert(numel(mj) >= 1, ...
                sprintf('工件 %d 工序 %d 无可用的可选机器', j, k));
        end
    end

    % --- 计算 makespan 归一化理论上界（改进3） ---
    % 上界 = 所有工序分别取各自最快可选机器工时后的总和（松弛上界，
    % 忽略机器冲突与工序约束），作为固定归一化分母，消除跨代量纲漂移。
    ub = 0;
    for j = 1:prob.nJob
        for k = 1:prob.nOpPerJob(j)
            tk = prob.op_time{j}{k};
            % 阶段3：单工序工时须为正有限标量；否则归一化分母将异常污染全部评估。
            if ~isvector(tk) || any(~isfinite(tk)) || any(tk <= 0)
                error('load_data:BadOpTime', ...
                      '工件 %d 工序 %d 的 operation_time 含非正或非法(Inf/NaN)工时', j, k);
            end
            ub = ub + min(tk);
        end
    end
    % 阶段3：归一化分母守卫——mk_ub 必须为正有限，避免 evaluate 中除以 0/Inf。
    if ~isfinite(ub) || ub <= 0
        error('load_data:BadUB', ...
              'makespan 归一化上界 mk_ub 计算为非正或非法(%.6g)，数据可能存在全零工时。', ub);
    end
    prob.mk_ub = ub;
    % 阶段一：负荷不均衡归一化物理上界 load_ub。
    % 负荷差 loadUnb = max(loadVec)-min(loadVec) 恒 ≤ 全部工序最快工时之和 = mk_ub
    % （所有工序堆到同一台最快机器时负荷差达到该上界，其余机器为 0）。
    % 用 load_ub（=mk_ub）而非 mk_ub 之外的量纲去归一化 loadUnb，可使 ld 与 mk
    % 处于同一数量级，恢复"双目标加权均衡"的真实语义（修复旧代码用 makespan
    % 上界 mk_ub 归一化 loadUnb 致 ld≈0.035 的量级压制）。evaluate 缺失本字段时
    % 回退 mk_ub，兼容 benchmarks/load_benchmark 旧路径（零回归）。
    prob.load_ub = ub;

    % --- 能力标志位（阶段1 新增，默认关闭，供后续变体扩展做特性判定）---
    % 当前纯标准 FJSP 实例均为 false；未来 SDST/AGV/能耗/动态/重入变体在
    % 数据载入时置对应标志为 true，各模块据标志选择性启用特性逻辑。
    prob.has_setup    = false;   % 顺序相关换型时间 (SDST)
    prob.has_agv      = false;   % AGV/运输约束
    prob.has_energy   = false;   % 能耗/绿色指标
    prob.has_dynamic  = false;   % 动态到达/机器故障重调度
    prob.is_reentrant = false;   % 重入加工 (RFJSP)
end
