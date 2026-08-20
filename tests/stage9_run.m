function stage9_run()
% stage9_run  Stage9 lightweight self-test (no full solve; verifies JSON export
% contract + default-off zero regression). Safe: does not call llmaoo solve.
% Run: cd to project root in MATLAB, then execute stage9_run

    fprintf('==== Stage9 (visualization export) lightweight self-test ====\n');
    rng(12345);

    % 1. export_result_json produces valid JSON
    fprintf('\n[1] export_result_json -> JSON\n');
    addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports');
    cfg = llmaoo_config();
    prob = load_data(cfg.DATA_FILE);
    % build a minimal fake result (same contract as llmaoo) to exercise serializer
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
    [sched, mk, lv] = decode(prob, chrom);
    res = struct();
    res.problem = prob;
    res.schedule = sched;
    res.makespan = mk;
    res.loadVec = lv;
    res.loadUnb = max(lv)-min(lv);
    res.iters = 10;
    res.nan_count = 0;
    res.elapsed_sec = 0.1;
    res.trace_best = 1:10;
    res.trace_mean = 2:11;
    res.pareto = struct('mk',[mk],'lb',[res.loadUnb],'Z',[0.5 0.5], ...
                         'obj3',[0.5, 0.5, NaN]);   % 2-obj run: energy dim NaN -> energy_n=[]
    outPath = fullfile(pwd, 'logs', 'stage9_export_test.json');
    export_result_json(res, outPath);
    assert(exist(outPath,'file')==2, 'export JSON file not written');
    % validate JSON parses (MATLAB jsondecode round-trip)
    txt = fileread(outPath);
    obj = jsondecode(txt);
    assert(isfield(obj,'schedule') && isfield(obj,'makespan'), 'JSON missing core fields');
    assert(obj.makespan == mk, 'JSON makespan mismatch');
    % Stage4 P2 guard: contract_version must be >=1.2 and energy_n present (2-obj -> empty)
    assert(isfield(obj,'contract_version') && str2double(obj.contract_version) >= 1.2, ...
           'contract_version must be >=1.2 after Stage4 pareto cleanup');
    assert(isfield(obj.pareto,'energy_n'), 'pareto.energy_n field missing (Stage4)');
    en = obj.pareto.energy_n;
    assert((~iscell(en) && numel(en) == 0) || (isnumeric(en) && isempty(en)), ...
           '2-obj run must export energy_n=[] (empty), not NaN');
    fprintf('  contract_version=%s, energy_n empty for 2-obj OK\n', obj.contract_version);
    % JSON schedule decodes to an array-of-arrays (cell of row vectors OR numeric matrix).
    % Robustly count rows: if cell array, length; if matrix, first dim.
    if iscell(obj.schedule)
        nRows = numel(obj.schedule);
    else
        nRows = size(obj.schedule, 1);
    end
    assert(nRows == numel(sched), 'JSON schedule row count mismatch');
    fprintf('  JSON written: %d schedule rows, makespan=%.2f OK\n', nRows, obj.makespan);
    % Stage5 E4 (schema guard): enforce SCHEMA contract on exported schedule
    % ([job,op,machine,start,finish,duration], finish>=start>=0, finite).
    validate_schedule(obj.schedule);
    fprintf('  validate_schedule OK (6-col, finish>=start>=0, finite)\n');

    % 2. zero regression: default cfg has EXPORT_JSON false
    fprintf('\n[2] default cfg EXPORT_JSON == false (zero regression)\n');
    assert(isfield(cfg,'EXPORT_JSON') && cfg.EXPORT_JSON == false, ...
           'EXPORT_JSON must default false for zero regression');
    fprintf('  EXPORT_JSON=false OK (llmaoo offline behavior unchanged)\n');

    % 3. Python availability probe (non-fatal): if python + plotly present, validate parse
    fprintf('\n[3] Python JSON parse probe (non-fatal)\n');
    [stat, out] = system('python -c "import json,sys; d=json.load(open(r''logs/stage9_export_test.json'')); print(len(d[\''schedule\'']))"');
    if stat == 0
        fprintf('  Python parsed JSON OK (schedule rows=%s)\n', strtrim(out));
    else
        fprintf('  Python/plotly not available in this env (skipped); JSON file is standard, parseable.\n');
    end

    % 4. dynamic replay frame export (Stage8 AOO_DYNAMIC path, read-only demo)
    fprintf('\n[4] dynamic_replay -> replay JSON\n');
    addpath('benchmarks'); addpath('exports');
    frames = dynamic_replay(prob, cfg);
    assert(numel(frames) >= 2, 'replay must have baseline + at least one event frame');
    assert(strcmp(frames(1).type,'baseline'), 'first frame must be baseline');
    rpath = fullfile(pwd, 'logs', 'stage9_replay_test.json');
    export_replay_json(frames, rpath);
    assert(exist(rpath,'file')==2, 'replay JSON not written');
    rt = jsondecode(fileread(rpath));
    assert(numel(rt.frames) == numel(frames), 'replay frame count mismatch');
    assert(rt.frames(1).time == 0, 'first replay frame time must be 0');
    % Stage5 P2 (5.2): replay 契约对称性核对——digital_twin.py 依赖 kind=='dynamic_replay'
    % 且 frames 非空才能路由到回放渲染分支。断言契约完整，避免"结果 JSON / 回放 JSON"
    % 两种契约被前端误用。
    assert(isfield(rt,'kind') && strcmp(rt.kind,'dynamic_replay'), ...
           'replay JSON must carry kind==''dynamic_replay'' (contract symmetry)');
    assert(isfield(rt,'frames') && ~isempty(rt.frames), ...
           'replay JSON must carry non-empty frames (contract symmetry)');
    fprintf('  replay contract OK (kind=dynamic_replay, %d non-empty frames)\n', numel(rt.frames));
    fprintf('  replay JSON written: %d frames (baseline + %d events) OK\n', ...
            numel(rt.frames), numel(rt.frames)-1);

    fprintf('\n==== Stage9 lightweight self-test ALL PASS ====\n');
end
