function stage_robustness_test()
% stage_robustness_test  Stage-Refine targeted robustness regression.
% Two focused tests that previously had no coverage and allowed the aoo_engine
% `opOf` misuse to ship:
%   (1) UNEQUAL-OPS instance: aoo_engine must run without out-of-range index on
%       jobs whose operation counts differ (the bug class that broke MK04/05/08/09/10).
%   (2) parse_fjs DUAL LAYOUT: both FJSPLib (layout A: 1st token = op-count) and
%       wrqccc (layout B: 1st token = op1 altCount) must parse to identical op_mach.
%
% SAFE / ADDITIVE: pure construction + parser/solver smoke; no solver semantics
% changed. Failure throws (caught by run_all gate [18]).

    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports');

    %% (1) unequal-ops synthetic prob (mirrors MK04: 15 jobs, 8 machines, unequal ops)
    fprintf('  [R1] build unequal-ops prob + run aoo_engine one generation\n');
    prob = synth_unequal_ops(15, 8);
    cfg = llmaoo_config();
    cfg.AOO_MAXGEN = 1; cfg.AOO_POP = 12;   % single generation smoke (fast)
    cfg.LLM_ENABLE = false;
    llm_state = default_llm_state(cfg);
    try
        [~, aoo] = aoo_engine(prob, cfg, llm_state, []);
    catch ME
        error('stage_robustness_test:R1', 'aoo_engine failed on unequal-ops prob: %s', ME.message);
    end
    assert(numel(aoo.conv_best) >= 1, 'aoo_engine produced no convergence record');
    fprintf('    R1 OK (unequal-ops prob solved, nOp=%d, jobs ops=[%d..%d])\n', ...
            prob.nOp, min(prob.nOpPerJob), max(prob.nOpPerJob));

    %% (2) parse_fjs dual layout
    fprintf('  [R2] parse_fjs layout A (op-count first) vs layout B (altCount first)\n');
    tmpA = fullfile(pwd, 'logs', '_robust_layoutA.fjs');
    tmpB = fullfile(pwd, 'logs', '_robust_layoutB.fjs');
    write_layoutA(tmpA);
    write_layoutB(tmpB);
    probA = load_benchmark('LAYOUTA', 'File', tmpA);
    probB = load_benchmark('LAYOUTB', 'File', tmpB);
    % Compare op_mach structure job-by-job (machine sets should match after mapping)
    assert(probA.nJob == probB.nJob && probA.nMachine == probB.nMachine, ...
           'layout A/B differ in job/machine counts');
    for j = 1:probA.nJob
        assert(numel(probA.op_mach{j}) == numel(probB.op_mach{j}), ...
               'layout A/B job %d op count mismatch', j);
        for k = 1:numel(probA.op_mach{j})
            assert(isequal(sort(probA.op_mach{j}{k}), sort(probB.op_mach{j}{k})), ...
                   'layout A/B job %d op %d machine set mismatch', j, k);
            assert(isequal(probA.op_time{j}{k}, probB.op_time{j}{k}), ...
                   'layout A/B job %d op %d time mismatch', j, k);
        end
    end
    delete(tmpA); delete(tmpB);
    fprintf('    R2 OK (layout A and B parse to identical op_mach/time, nJob=%d nMachine=%d)\n', ...
            probA.nJob, probA.nMachine);
end

function prob = synth_unequal_ops(nJob, nMachine)
% synth_unequal_ops  Build a prob with deliberately UNEQUAL ops-per-job (so the
% job-internal op index accumulator path in aoo_engine is genuinely exercised),
% but every op eligible on all machines (so decode never fails for unrelated reasons).
    op_mach = cell(nJob, 1);
    op_time = cell(nJob, 1);
    rng(42);
    for j = 1:nJob
        nOps = randi([3 8]);   % unequal across jobs
        op_mach{j} = cell(1, nOps);
        op_time{j} = cell(1, nOps);
        for k = 1:nOps
            op_mach{j}{k} = 1:nMachine;            % all machines eligible
            op_time{j}{k} = randi([1 9], 1, nMachine);
        end
    end
    totalOps = sum(cellfun(@numel, op_time));
    prob = assemble_prob_local(op_mach, op_time, nMachine, nJob, totalOps, 'synth_unequal');
end

function prob = assemble_prob_local(op_mach, op_time, numMachines, numJobs, totalOps, src)
% assemble_prob_local  Local copy of load_benchmark.assemble_prob (kept private to
% this test so it does not depend on the nested function being callable directly).
    machW = ones(numMachines, 1);
    nOpPerJob = cellfun(@numel, op_time).';
    idx = 0;
    opGlobal = zeros(numJobs, max(nOpPerJob));
    jobOf = zeros(1, totalOps);
    opOf = zeros(1, totalOps);
    for j = 1:numJobs
        for k = 1:nOpPerJob(j)
            idx = idx + 1;
            opGlobal(j, k) = idx;
            jobOf(idx) = j;
            opOf(idx) = k;
        end
    end
    mk_ub = 0;
    for j = 1:numJobs
        for k = 1:numel(op_time{j})
            mk_ub = mk_ub + min(op_time{j}{k});
        end
    end
    prob = struct();
    prob.nJob = numJobs; prob.nOp = totalOps; prob.nMachine = numMachines;
    prob.machW = machW; prob.op_mach = op_mach; prob.op_time = op_time;
    prob.nOpPerJob = nOpPerJob; prob.opGlobal = opGlobal; prob.jobOf = jobOf;
    prob.opOf = opOf; prob.mk_ub = mk_ub; prob.name = src;
    prob.has_setup = false; prob.has_agv = false; prob.has_energy = false;
    prob.has_dynamic = false; prob.is_reentrant = false; prob.bks = NaN;
end

function write_layoutA(fn)
% FJSPLib layout A: header "nJob nMachine", then per job one line:
%   [jobIdx] nOps (alt m t m t ...) x nOps
% Op1's altCount is set EQUAL to nOps so that layout A (with explicit op-count
% prefix) and layout B (no prefix) both parse to the identical structure.
    fid = fopen(fn, 'w');
    fprintf(fid, '3 4\n');
    % job1: 2 ops, op1 altCount=2 (== nOps) -> m1=1 t=3, m2=2 t=4 ; op2 same
    fprintf(fid, '1 2  2 1 3 2 4   2 1 3 2 4\n');
    % job2: 3 ops, op1 altCount=3 (== nOps)
    fprintf(fid, '2 3  3 1 3 2 4 3 5   3 1 3 2 4 3 5   3 1 3 2 4 3 5\n');
    % job3: 2 ops
    fprintf(fid, '3 2  2 1 3 2 4   2 1 3 2 4\n');
    fclose(fid);
end

function write_layoutB(fn)
% wrqccc layout B: identical data but WITHOUT the per-job op-count prefix, so the
% first token of the line is op1's altCount (which equals nOps, keeping it
% unambiguous and consistent with layout A).
    fid = fopen(fn, 'w');
    fprintf(fid, '3 4\n');
    fprintf(fid, '2 1 3 2 4   2 1 3 2 4\n');
    fprintf(fid, '3 1 3 2 4 3 5   3 1 3 2 4 3 5   3 1 3 2 4 3 5\n');
    fprintf(fid, '2 1 3 2 4   2 1 3 2 4\n');
    fclose(fid);
end
