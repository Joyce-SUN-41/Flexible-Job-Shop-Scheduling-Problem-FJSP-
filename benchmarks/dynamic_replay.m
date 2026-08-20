function frames = dynamic_replay(prob, cfg, on_event, elite)
% dynamic_replay  Stage4 (dynamic reschedule + digital-twin linkage): generate a
%   dynamic-rescheduling frame sequence for replay. Baseline schedule is computed by
%   decode; at each event time (from perturbation), the schedule is locally re-solved
%   by re-decoding the remaining open operations after applying the disturbance.
%   Returns a struct array `frames` with fields:
%     .time      : event time (0 = baseline)
%     .type      : 'baseline' or event type
%     .desc      : human-readable description
%     .schedule  : cell array of [job,op,machine,start,finish,duration] rows
%   Safe: read-only on prob; does NOT modify decode/evaluate numerics.
%   on_event(evt, schedule, t) is an optional user hook returning a modified schedule.
%
%   Stage4 ADDITIVE: optional 4th arg `elite` (the AOO optimal chromosome from
%   llmaoo). When provided, the baseline uses the REAL solver-optimal schedule
%   (decode(prob, elite)) instead of a random chrom, so the replay visualization
%   reflects the true best solution, not a random one. When omitted (nargin<4), the
%   original random fallback baseline is kept for backward compatibility.
%
% NOTE: this is a lightweight STRUCTURAL demo of dynamic reschedule (not the full
% predictive-reactive solver). It demonstrates the perturbation->re-decode loop so
% the Python replay can visualize "disturbance -> reschedule" robustness. The full
% reactive main loop belongs to aoo_engine Stage8 (AOO_DYNAMIC), kept separate.

    if nargin < 3, on_event = []; end
    if nargin < 4 || isempty(elite)
        useElite = false;
    else
        useElite = isstruct(elite) && isfield(elite,'OS') && isfield(elite,'MS');
    end
    addpath('benchmarks');

    % --- baseline ---
    % Stage4: prefer the real AOO-optimal chromosome (elite) when available;
    % fall back to a random feasible chrom for backward compatibility.
    if useElite
        [sched0, mkBase, ~] = decode(prob, elite, cfg);
        baseSrc = 'aoo_elite';   % real solver-optimal baseline
    else
        order = [];
        for j=1:prob.nJob, order = [order, repmat(j, 1, prob.nOpPerJob(j))]; end
        os = order(randperm(length(order)));
        ms = zeros(1, sum(prob.nOpPerJob));
        jobOpPtr = zeros(1, prob.nJob);
        for t=1:length(os)
            j = os(t); jobOpPtr(j) = jobOpPtr(j)+1;
            machSet = prob.op_mach{j}{jobOpPtr(j)};
            ms(t) = machSet(randi(length(machSet)));
        end
        chrom = struct('OS', os(:).', 'MS', ms);
        [sched0, mkBase, ~] = decode(prob, chrom);
        baseSrc = 'random_fallback';
    end
    frames(1).time = 0;
    frames(1).type = 'baseline';
    frames(1).desc = ['baseline schedule (' baseSrc ')'];
    frames(1).schedule = sched_to_rows(sched0);
    frames(1).makespan = mkBase;   % Stage4: expose baseline makespan for comparison views

    % --- events at fixed sample times (for demo only) ---
    evtTimes = [round(prob.mk_ub*0.3), round(prob.mk_ub*0.6)];
    for q = 1:numel(evtTimes)
        t = evtTimes(q);
        type = 'machine_breakdown';
        evt = perturbation(prob, t, type, 'machine', mod(q,prob.nMachine)+1, 'dur', 8);
        % structural re-decode: shift operations starting after t on the down machine
        schedR = reschedule_after_event(prob, sched0, evt);
        if ~isempty(on_event)
            try, schedR = on_event(evt, schedR, t); end
        end
        frames(end+1).time = t;
        frames(end).type = type;
        frames(end).desc = evt.desc;
        sr = sched_to_rows(schedR);
        frames(end).schedule = sr;
        % Stage4: give every frame a makespan so the struct array field set is
        % consistent (MATLAB jsonencode only emits common fields across the array);
        % used by the dashboard static-vs-dynamic comparison view.
        finishes = cellfun(@(r) r(5), sr);
        frames(end).makespan = max(finishes);
    end
end

function rows = sched_to_rows(sched)
    rows = {};
    for i = 1:numel(sched)
        rows{end+1} = [sched(i).job, sched(i).op, sched(i).machine, ...
                       sched(i).start, sched(i).finish, sched(i).duration];
    end
end

function schedR = reschedule_after_event(prob, sched0, evt)
    % simplest reactive strategy for demo: keep operations that finished before the
    % disturbance; for operations on the down machine starting at/after evt.time,
    % re-insert them after the breakdown window on the same machine (conservative).
    schedR = sched0;
    m = evt.machine; tend = evt.time + evt.dur;
    for i = 1:numel(schedR)
        if schedR(i).machine == m && schedR(i).start >= evt.time
            % push finish by the downtime; keep relative ordering
            delay = tend - schedR(i).start;
            if delay > 0
                schedR(i).start = schedR(i).start + delay;
                schedR(i).finish = schedR(i).finish + delay;
            end
        end
    end
end
