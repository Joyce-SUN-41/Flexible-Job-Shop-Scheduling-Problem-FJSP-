%% decode.m — 解码单个染色体 -> semi-active 调度（半主动调度）
% 返回：schedule（每工序的机器/起止时间）、makespan、机器负荷向量
% schedule 为结构体数组，字段：job, op, machine, start, finish, duration
%
% 解码策略（semi-active 半主动解码）：
%   工序的执行次序由 OS 决定（保证工序优先级约束），机器由 MS 选定。
%   对于已选定机器的工序，采用“全局机器就绪插入”法：在机器就绪时间轴上
%   寻找满足「工件前序已完成」的最早可插入时刻，使该工序尽可能前移且
%   不被后续同机工序阻塞。
%   注：本解码为 semi-active（能利用机器空闲间隙前插），但并非 true active
%   调度（不保证“将某工序左移不会推迟任何其他工序”的全局重排性质）。
%   若需进一步压榨 makespan，可在解码后接 active 化后处理或关键路径邻域。

function [schedule, makespan, loadVec] = decode(prob, chrom, cfg)
    % --- 入口防御（阶段2：fail-fast，避免静默错误传播）---
    if ~isstruct(chrom) || ~isfield(chrom,'OS') || ~isfield(chrom,'MS')
        error('decode:BadChrom', 'chrom 必须是含 OS/MS 字段的标量 struct');
    end
    OS = chrom.OS(:).'; MS = chrom.MS(:).';   % 强制行向量，避免列向量导致位置错配
    nOp   = prob.nOp;
    nMach = prob.nMachine;
    if numel(OS) ~= nOp || numel(MS) ~= nOp
        error('decode:LengthMismatch', ...
              'chrom.OS/MS 长度(%d/%d) 必须等于 prob.nOp(%d)', numel(OS), numel(MS), nOp);
    end
    % 阶段3：fail-fast 防御（避免 NaN/Inf 或非法工件号静默污染调度求解）
    if any(~isfinite(OS)) || any(~isfinite(MS))
        error('decode:BadChrom', 'chrom.OS/MS 含 NaN/Inf 元素，无法解码');
    end
    if any(OS < 1) || any(OS > prob.nJob) || any(round(OS) ~= OS)
        error('decode:BadChrom', 'chrom.OS 含非法工件号（须为 1..%d 的整数）', prob.nJob);
    end

    % 机器就绪时间轴：记录每台机器上已占用区间 [start, finish]
    % 用区间列表表示，便于在空闲间隙中插入
    machInt = cell(1, nMach);
    for m = 1:nMach, machInt{m} = zeros(0, 2); end
    jobReady  = zeros(1, prob.nJob);   % 工件前序工序的最早可开始时刻
    jobOpCount = zeros(1, prob.nJob);
    jobLastMach = zeros(1, prob.nJob); % last machine of each job (Stage8 AGV transport start)

    schedule = repmat(struct('job',0,'op',0,'machine',0, ...
                  'start',0,'finish',0,'duration',0), 1, nOp);

    % Stage8: AGV transport constraint (default off, zero regression). Enabled when
    %   prob.has_agv is true AND (cfg.AOO_AGV or prob.AOO_AGV). aoo_engine passes cfg;
    %   standalone tests may pass prob flag. Guard nargin<3 (decode called without cfg).
    if nargin >= 3 && ~isempty(cfg)
        agvOn = (isfield(cfg,'AOO_AGV') && cfg.AOO_AGV) || (isfield(prob,'AOO_AGV') && prob.AOO_AGV);
    else
        agvOn = false;
    end
    useAGV = (nargin >= 3 && ~isempty(cfg) && agvOn && ...
              isfield(prob, 'has_agv') && prob.has_agv);

    for t = 1:nOp
        j = OS(t);
        jobOpCount(j) = jobOpCount(j) + 1;
        k = jobOpCount(j);                      % 当前工序序号
        machSet = prob.op_mach{j}{k};
        timeSet = prob.op_time{j}{k};
        mIdx    = MS(t);                         % 所选机器在可选集中的索引
        mIdx    = min(max(mIdx, 1), length(machSet)); % 安全钳制，防止越界
        m       = machSet(mIdx);
        p       = timeSet(mIdx);

        % Stage8: AGV transport time (prev op machine -> current machine)
        if useAGV
            prevM = jobLastMach(j);
            if prevM > 0 && prevM ~= m && m >= 1 && m <= prob.nMachine && ...
               prevM >= 1 && prevM <= prob.nMachine
                transT = prob.agv_time(prevM, m);
            else
                transT = 0;
            end
        else
            transT = 0;
        end

        % 在机器 m 上寻找最早可行插入点（阶段4：二分定位，O(log n) 替代线性扫描）：
        % 候选起点 = {jobReady(j)+transT} ∪ {每个已占用区间的结束时刻}
        % 取其中 >= jobReady(j)+transT 且不与任何已占用区间重叠的最早时刻。
        % 语义与旧线性扫描完全一致，仅把"找首个可行间隙"改为排序区间二分。
        est0 = jobReady(j) + transT;   % Stage8: earliest start after AGV transport
        ints = machInt{m};        % Nx2 区间矩阵，按 start 升序（insert_interval 维持）
        if isempty(ints)
            st = est0;            % 机器空闲：直接从前序就绪+运输时刻开始
        else
            est = est0;
            starts = ints(:,1);   % 升序
            ends   = ints(:,2);   % 升序
            % 候选起点集 = {est, ends(1), ends(2), ...}（间隙右端），按 ends 升序天然有序
            % 二分：找第一个 ends(i) <= est 之后的首个不重叠间隙；否则检查 est 本身落在
            % [ends(i), starts(i+1)] 间隙内。
            st = -1;
            % 情况A：est 之前没有区间结束（est <= starts(1)），则直接从 est 开始
            if est <= starts(1)
                st = est;
            else
                % 找最后一个结束时刻 <= est 的区间位置（二分）
                lo = 1; hi = size(ints,1);
                lastEndBefore = 0;
                while lo <= hi
                    mid = floor((lo+hi)/2);
                    if ends(mid) <= est
                        lastEndBefore = mid; lo = mid + 1;
                    else
                        hi = mid - 1;
                    end
                end
                % 检查 est 本身是否落在 [ends(lastEndBefore), starts(lastEndBefore+1)] 间隙
                if lastEndBefore == 0
                    % est 在第一个区间之前但 > starts(1) 已被上面分支覆盖，安全回退
                    st = max(est, ends(1));
                elseif lastEndBefore < size(ints,1)
                    gapStart = max(est, ends(lastEndBefore));
                    gapEnd   = starts(lastEndBefore + 1);
                    if gapStart + p <= gapEnd + 1e-12
                        st = gapStart;            % est 可容纳于该间隙
                    end
                end
                % 情况B：est 落在某区间内（被占用）→ 跳到该区间结束后再试后续间隙
                if st < 0
                    % 从 lastEndBefore+1 起的后续间隙逐个二分检查（间隙数 <= nOp，整体仍 O(log n) 期望）
                    probe = lastEndBefore + 1;
                    while probe <= size(ints,1)
                        gapStart = max(est, ends(probe));   % 区间 probe 结束后续间隙起点
                        if probe == size(ints,1)
                            st = gapStart; break;           % 末尾追加
                        end
                        gapEnd = starts(probe + 1);
                        if gapStart + p <= gapEnd + 1e-12
                            st = gapStart; break;
                        end
                        probe = probe + 1;
                    end
                    if st < 0, st = max(est, ends(end)); end   % 末尾兜底
                end
            end
        end
        ft = st + p;

        % 记录区间（保持按 start 升序）
        machInt{m} = insert_interval(machInt{m}, st, ft);

        schedule(t).job      = j;
        schedule(t).op       = k;
        schedule(t).machine  = m;
        schedule(t).start    = st;
        schedule(t).finish   = ft;
        schedule(t).duration = p;

        jobReady(j) = ft;     % 该工件下一工序最早开始 = 本工序完成
        jobLastMach(j) = m;   % Stage8: record last machine for next op AGV transport
    end

    % 阶段5 修复：cellfun 默认 UniformOutput 下 max 对空区间返回非标量会报错；
    % 向列向量追加 -Inf 保证空区间也返回标量 -Inf（空机不影响 makespan）。
    machFin = cellfun(@(x) max([x(:,2); -Inf], [], 'omitnan'), ...
                      machInt, 'UniformOutput', false);
    makespan = max(cell2mat(machFin));
    if isempty(makespan) || isnan(makespan), makespan = 0; end

    loadVec  = zeros(1, nMach);
    for t = 1:nOp
        m = schedule(t).machine;
        loadVec(m) = loadVec(m) + schedule(t).duration;
    end

    % 阶段7：可选 active 化解码后处理（默认关，零回归）。
    % active 调度保证"将任一工序左移不会推迟任何其他工序"，可进一步压榨 makespan。
    % 仅在调用方显式传入 cfg 且开启 AOO_ACTIVE_DECODE 时执行；其余所有既有调用
    % （decode(prob, chrom) 无第三参）语义完全不变。
    if nargin >= 3 && ~isempty(cfg) && isfield(cfg, 'AOO_ACTIVE_DECODE') && cfg.AOO_ACTIVE_DECODE
        [schedule, makespan, loadVec] = active_postprocess(prob, chrom, schedule, makespan, loadVec);
    end
end

%% 阶段7：active 调度后处理（Giffler-Thompson 式机器择优 + 关键工序左移）
% 对 semi-active 调度中每个工序，尝试将其改派到能使 finish 更早的可选机器，
% 并在不推迟同机后续工序前提下尽量左移。仅在确实改善 makespan 时接受。
function [schedule, makespan, loadVec] = active_postprocess(prob, chrom, schedule, makespan, loadVec)
    nOp = prob.nOp;
    % 反复扫描关键工序并改机器，直到一轮无改善（受限迭代，避免 O(n^2) 爆炸）
    improved = true; guard = 0;
    while improved && guard < 5
        improved = false; guard = guard + 1;
        % 当前各机器时间占用（用于左移可行性判断）
        for t = 1:nOp
            j = schedule(t).job; k = schedule(t).op; kk = prob.opOf(t);
            machSet = prob.op_mach{j}{kk};
            if length(machSet) <= 1, continue; end
            curM = schedule(t).machine;
            curFin = schedule(t).finish;
            bestM = curM; bestFin = curFin;
            for mi = 1:length(machSet)
                m = machSet(mi);
                if m == curM, continue; end
                % 估算改派到机器 m 的最早可行开始（简化：机器就绪 + 前序工件完成）
                p = prob.op_time{j}{kk}(mi);
                st = machine_earliest_start(prob, schedule, t, m, p);
                ft = st + p;
                if ft < bestFin - 1e-9
                    bestM = m; bestFin = ft;
                end
            end
            if bestM ~= curM
                % 应用改派
                oldM = curM;
                loadVec(oldM) = loadVec(oldM) - schedule(t).duration;
                schedule(t).machine = bestM;
                schedule(t).start = machine_earliest_start(prob, schedule, t, bestM, ...
                    prob.op_time{j}{kk}(find(machSet == bestM)));
                schedule(t).finish = schedule(t).start + prob.op_time{j}{kk}(find(machSet == bestM));
                loadVec(bestM) = loadVec(bestM) + schedule(t).duration;
                improved = true;
            end
        end
        % 更新 makespan
        newMk = max([schedule.finish]);
        if newMk < makespan - 1e-9
            makespan = newMk;
        end
    end
end

%% 估算工序 t 改派到机器 m 的最早可行开始（考虑工件前序完成 + 机器已占用区间）
function st = machine_earliest_start(prob, schedule, t, m, p)
    % 工件前序：同一 job 的前序工序 finish
    j = schedule(t).job; k = schedule(t).op;
    jobPred = -Inf;
    for q = 1:prob.nOp
        if schedule(q).job == j && schedule(q).op < k
            jobPred = max(jobPred, schedule(q).finish);
        end
    end
    % 机器已占用区间（排除 t 自身）
    occEnd = -Inf;
    for q = 1:prob.nOp
        if q == t, continue; end
        if schedule(q).machine == m
            occEnd = max(occEnd, schedule(q).finish);
        end
    end
    st = max(jobPred, occEnd);
end

% 将区间 [s,f] 插入并按 start 升序保持
function ints = insert_interval(ints, s, f)
    ints(end+1, :) = [s, f];
    ints = sortrows(ints, 1);
end
