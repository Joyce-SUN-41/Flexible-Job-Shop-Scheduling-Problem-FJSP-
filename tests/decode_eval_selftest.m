%% decode_eval_selftest.m — 阶段2 自测：decode/evaluate 正确性与防御校验
% 纯校验脚本，不修改任何文件、不改变主流程结果。
% 运行： decode_eval_selftest   （或 matlab -batch "decode_eval_selftest; exit"）

function decode_eval_selftest()
    cfg = llmaoo_config();
    rng(cfg.RNG_SEED);
    prob = load_data(cfg.DATA_FILE);
    nOp = prob.nOp; nMach = prob.nMachine;
    pass = 0; fail = 0;

    % ---------- 1. decode 输出不变量校验（随机 200 染色体） ----------
    nTest = 200;
    for i = 1:nTest
        X = rand(1, 2*nOp);
        [~, order] = sort(X(1:nOp), 'descend');
        OS = prob.jobOf(order);
        MS = zeros(1, nOp); seen = zeros(1, prob.nJob);
        for t = 1:nOp
            j = OS(t); seen(j) = seen(j)+1; kk = seen(j);
            nM = length(prob.op_mach{j}{kk});
            MS(t) = min(max(floor(X(nOp+t)*nM)+1, 1), nM);
        end
        chrom = struct('OS', OS, 'MS', MS);
        [sched, mk, loadVec] = decode(prob, chrom);

        % (a) OS 工序数守恒
        cnt = zeros(1, prob.nJob);
        for t = 1:nOp, cnt(OS(t)) = cnt(OS(t))+1; end
        okA = isequal(cnt, prob.nOpPerJob);
        % (b) MS 范围合法（逐工序：上限为该工序对应作业的可选机器数）
        upper = zeros(1, nOp); seenB = zeros(1, prob.nJob);
        for t = 1:nOp
            j = OS(t); seenB(j) = seenB(j)+1; kk = seenB(j);
            upper(t) = length(prob.op_mach{j}{kk});
        end
        okB = all(MS >= 1) && all(MS <= upper);
        % (c) loadVec 与 sched 自洽
        lv = zeros(1, nMach);
        for t = 1:nOp, lv(sched(t).machine) = lv(sched(t).machine) + sched(t).duration; end
        okC = isequal(lv, loadVec);
        % (d) makespan == 所有调度工序的最大 finish
        okD = abs(mk - max([sched.finish])) < 1e-9;
        % (e) 每工序 start+duration == finish
        okE = all(abs([sched.start] + [sched.duration] - [sched.finish]) < 1e-9);

        if okA && okB && okC && okD && okE
            pass = pass + 1;
        else
            fail = fail + 1;
            fprintf('FAIL decode invariant @%d: A=%d B=%d C=%d D=%d E=%d\n', ...
                    i, okA, okB, okC, okD, okE);
        end
    end

    % ---------- 2. evaluate 确定性（同 chrom 两次一致） ----------
    X = rand(1, 2*nOp);
    [~, order] = sort(X(1:nOp), 'descend');
    OS = prob.jobOf(order); MS = zeros(1, nOp); seen = zeros(1, prob.nJob);
    for t = 1:nOp
        j = OS(t); seen(j) = seen(j)+1; kk = seen(j);
        nM = length(prob.op_mach{j}{kk});
        MS(t) = min(max(floor(X(nOp+t)*nM)+1, 1), nM);
    end
    chrom = struct('OS', OS, 'MS', MS);
    [Z1, mk1, ~, ~] = evaluate(prob, chrom, [1 1]);
    [Z2, mk2, ~, ~] = evaluate(prob, chrom, [1 1]);
    if abs(Z1-Z2) < 1e-12 && abs(mk1-mk2) < 1e-12
        pass = pass + 1;
    else
        fail = fail + 1;
        fprintf('FAIL evaluate determinism: Z1=%.6f Z2=%.6f\n', Z1, Z2);
    end

    % ---------- 3. 防御：非法输入应报错 ----------
    % (a) 长度错误 OS
    bad1 = struct('OS', ones(1, nOp-1), 'MS', ones(1, nOp));
    if throws(@() decode(prob, bad1)), pass = pass + 1; else fail = fail+1; fprintf('FAIL defense length\n'); end
    % (b) 非 struct
    if throws(@() decode(prob, 'notstruct')), pass = pass + 1; else fail = fail+1; fprintf('FAIL defense struct\n'); end
    % (c) evaluate 空权重回退默认（不报错）
    try
        evaluate(prob, chrom, []); pass = pass + 1;
    catch
        fail = fail + 1; fprintf('FAIL eval empty weight\n');
    end
    % (d) evaluate 权重长度：长度2（双目标）与长度3（Stage8 三目标，含能耗）均合法；
    %     长度 4 等非法长度才应报错。Stage8 扩展后 3-权重为有效输入，不再抛异常。
    if throws(@() evaluate(prob, chrom, [1 1 1 1])), pass = pass + 1; else fail = fail+1; fprintf('FAIL defense wlen\n'); end

    % ---------- 4. semi-active 不弱于纯贪心追加（正确性不变量） ----------
    % 贪心版：每工序直接追加到其机器末尾（无间隙前插）；semi-active 应能 <= 它
    nCmp = 100; worse = 0;
    for i = 1:nCmp
        X = rand(1, 2*nOp);
        [~, order] = sort(X(1:nOp), 'descend');
        OS = prob.jobOf(order); MS = zeros(1, nOp); seen = zeros(1, prob.nJob);
        for t = 1:nOp
            j = OS(t); seen(j) = seen(j)+1; kk = seen(j);
            nM = length(prob.op_mach{j}{kk});
            MS(t) = min(max(floor(X(nOp+t)*nM)+1, 1), nM);
        end
        chrom = struct('OS', OS, 'MS', MS);
        [~, mkSemi, ~] = decode(prob, chrom);
        mkGreedy = greedy_append(prob, chrom);
        if mkSemi > mkGreedy + 1e-9, worse = worse + 1; end
    end
    if worse == 0, pass = pass + 1; else fail = fail + 1;
        fprintf('FAIL semi-active worse than greedy in %d/%d cases\n', worse, nCmp);
    end

    fprintf('\n=== decode_eval_selftest: PASS=%d FAIL=%d ===\n', pass, fail);
    if fail > 0, error('selftest failed'); end
end

%% 辅助：纯贪心追加解码（无间隙前插），用于不变量对比
function mk = greedy_append(prob, chrom)
    nOp = prob.nOp; OS = chrom.OS; MS = chrom.MS;
    machEnd = zeros(1, prob.nMachine);
    jobReady = zeros(1, prob.nJob); jobOpCount = zeros(1, prob.nJob);
    for t = 1:nOp
        j = OS(t); jobOpCount(j) = jobOpCount(j)+1; k = jobOpCount(j);
        machSet = prob.op_mach{j}{k}; timeSet = prob.op_time{j}{k};
        mIdx = min(max(MS(t),1), length(machSet));
        m = machSet(mIdx); p = timeSet(mIdx);
        st = max(jobReady(j), machEnd(m));
        ft = st + p;
        machEnd(m) = ft; jobReady(j) = ft;
    end
    mk = max(machEnd);
end

%% 辅助：检测函数句柄是否抛错
function tf = throws(fh)
    tf = false;
    try fh(); catch, tf = true; end
end
