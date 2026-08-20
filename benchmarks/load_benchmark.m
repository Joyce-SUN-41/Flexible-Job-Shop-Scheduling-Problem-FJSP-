function prob = load_benchmark(name, varargin)
% load_benchmark  Load a standard FJSP benchmark instance into the LLMAOO 'prob' structure.
%
%   prob = load_benchmark('MK01')        returns the built-in Brandimarte MK01
%                                        instance (10 jobs, 6 machines, 55 ops),
%                                        best-known makespan (BKS) = 40.
%   prob = load_benchmark('data')        loads the project's own data.mat via load_data.
%   prob = load_benchmark('MK01','File',path)  loads an external .fjs benchmark file
%                                        using the standard flexible-job-shop text
%                                        format (see parse_fjs). This is how the full
%                                        Brandimarte MK01-MK10 / Hurink / Kacem sets
%                                        are loaded offline.
%
% The returned 'prob' is fully compatible with decode / evaluate_population / aoo_engine,
% so no change to the core solver is required. This file is additive only (safe for the
% main chain): it does NOT modify decode / evaluate / aoo_engine / llmaoo.
%
% Reference datasets:
%   - Brandimarte M. (1993), "Routing and scheduling in a flexible job shop by
%     genetic algorithms", JORS 45(2):168-176. MK01-MK10.
%   - Hurink J. et al. (1994), OR Spektrum. edata / rdata / vdata.
%   - Kacem I. et al. (2002), IJPR 40(13):3041-3058. 8x8, 10x10, 15x10.
% Full MK instances can be obtained from public repositories such as
%   https://github.com/SchedulingLab/fjsp-instances (drop the .fjs files next to this
%   script and call load_benchmark('MK02','File','MK02.fjs') etc.).
%
% SAFE / ADDITIVE: no edit to existing solver files.

    p = inputParser;
    addParameter(p, 'File', '', @ischar);
    parse(p, varargin{:});

    if strcmpi(name, 'data')
        cfg = llmaoo_config();
        prob = load_data(cfg.DATA_FILE);
        prob.name = 'data(mat)';
        return;
    end

    if ~isempty(p.Results.File)
        prob = parse_fjs(p.Results.File);
        prob.name = name;
        return;
    end

    switch upper(name)
        case 'MK01'
            prob = builtin_mk01();
        otherwise
            % ADDITIVE: auto-locate a standard .fjs file for MK02-MK10 (and other
            % sets dropped under ./data) so the full benchmark can run without
            % manually passing 'File'. Looks for ./data/<NAME>.fjs with case
            % flexibility. If absent, raises a clear data-dependency error
            % (does NOT fabricate instances).
            auto = find_fjs(name);
            if ~isempty(auto)
                prob = parse_fjs(auto);
                prob.name = upper(name);
                attach_bks(prob, upper(name));   % 注入标准 Brandimarte BKS 参考值（仅参考，不修改求解）
                return;
            end
            error('load_benchmark:unknown', ...
                ['Unknown benchmark ''%s''. Built-in: MK01 (or auto-detected under ./data). ', ...
                 'For MK02-MK10 / Hurink / Kacem, drop the standard .fjs file into ./data ', ...
                 'and call load_benchmark(''%s'') (auto-detected), or pass (name,''File'',path).'], ...
                name, name);
    end
end

function attach_bks(prob, name)
% attach_bks  Inject well-known BKS (best-known makespan) reference values for
% standard Brandimarte MK instances. These are published literature values
% (Brandimarte 1993), used ONLY for gap reporting in benchmark tables; they do
% NOT affect the solver numerics. Instances not in the table keep prob.bks=NaN.
    BKS = struct('MK01',40, 'MK02',26, 'MK03',204, 'MK04',81, 'MK05',173, ...
                 'MK06',55, 'MK07',144, 'MK08',523, 'MK09',311, 'MK10',297);
    if isfield(BKS, name)
        prob.bks = BKS.(name);
    else
        prob.bks = NaN;   % 非标准实例保持 NaN，不伪造
    end
end

function fn = find_fjs(name)
% find_fjs  Locate a standard .fjs benchmark file under ./data (case-flexible).
% Returns '' when not found (caller decides how to handle the data dependency).
    fn = '';
    cand = {sprintf('data/%s.fjs', name), ...
            sprintf('data/%s.fjs', upper(name)), ...
            sprintf('data/%s.fjs', lower(name)), ...
            sprintf('data/%s.fjs', [upper(name(1)), lower(name(2:end))]), ...  % Title-case (Mk03)
            sprintf('benchmarks/instances/%s.fjs', upper(name))};
    for k = 1:numel(cand)
        if isfile(cand{k})
            fn = cand{k};
            return;
        end
    end
end

function prob = parse_fjs(fn)
% parse_fjs  Parse a standard flexible-job-shop benchmark text file.
% Two widely-used layouts are both supported:
%   (A) FJSPLib / Brandimarte standard: one line per JOB, first token = number
%       of operations for that job, then N operation blocks of the form
%       <altCount> <m1> <t1> <m2> <t2> ...  (machines/times for each alt).
%         <numJobs> <numMachines>
%         <nOps_j> <alt> m t m t ...  <alt> m t ...   (job 1, all ops on one line)
%         ...
%       Lines may begin with an optional job index (e.g. "1  <nOps> ...") -> skipped.
%   (B) One line per OPERATION: first token = altCount, optionally preceded by a
%       job index; multiple lines per job. The parser falls back to this when a
%       single line does not contain a full job's worth of operation blocks.
% Machine indices are remapped to a dense 1..K set afterwards (see assemble_prob
% call below) so non-contiguous / out-of-range IDs never break decode().
    fid = fopen(fn, 'r');
    if fid < 0, error('load_benchmark:file', 'Cannot open benchmark file: %s', fn); end
    cleanup = onCleanup(@() fclose(fid));

    hdr = fgetl(fid);
    nums = sscanf(regexprep(hdr, '[^\d\s]', ' '), '%f').';
    numJobs = nums(1); numMachines = nums(2);

    op_mach = cell(numJobs, 1);
    op_time = cell(numJobs, 1);
    totalOps = 0;

    rawLines = {};
    while ~feof(fid)
        line = fgetl(fid);
        if ~isempty(strtrim(line)), rawLines{end+1} = line; end
    end
    li = 1;  % line cursor (one line per job in all standard Brandimarte layouts)

    for j = 1:numJobs
        if li > numel(rawLines)
            error('load_benchmark:format', 'Unexpected EOF: not enough lines for %d jobs in %s', numJobs, fn);
        end
        toks = sscanf(regexprep(rawLines{li}, '[^\d\s]', ' '), '%f').';
        idx = 1;
        % Skip optional leading job index if the first token equals the job number.
        if numel(toks) >= 1 && toks(1) == j && numel(toks) > 1
            idx = 2;
        end
        machines = {}; times = {}; jobsOpsCount = 0;

        % Try Layout (A): first remaining token is the OPERATION COUNT for this job.
        % Valid only if reading exactly that many blocks consumes the WHOLE line
        % (no leftover tokens). Otherwise the first token is actually op1's altCount.
        nOps = [];
        if numel(toks) >= idx && toks(idx) >= 1 && toks(idx) <= 100
            trial = toks(idx);
            ti = idx + 1; ok = true;
            for o = 1:trial
                if ti > numel(toks), ok = false; break; end
                a = toks(ti); ti = ti + 1;
                if ti + 2*a - 1 > numel(toks), ok = false; break; end
                ti = ti + 2*a;
            end
            if ok && ti == numel(toks) + 1
                nOps = trial;
            end
        end

        if ~isempty(nOps)
            % Layout (A): read exactly nOps blocks from this single line.
            idx = idx + 1;
            for o = 1:nOps
                alt = toks(idx); idx = idx + 1;
                m = []; t = [];
                for a = 1:alt
                    m(end+1) = toks(idx); idx = idx + 1;
                    t(end+1) = toks(idx); idx = idx + 1;
                end
                jobsOpsCount = jobsOpsCount + 1;
                machines{jobsOpsCount} = m(:).';
                times{jobsOpsCount} = t(:).';
            end
        else
            % Layout (B): first token is op1's altCount; read ALL blocks on this line
            % (one line carries the whole job). No cross-line merging.
            while idx <= numel(toks)
                alt = toks(idx); idx = idx + 1;
                m = []; t = [];
                for a = 1:alt
                    if idx <= numel(toks), m(end+1) = toks(idx); idx = idx + 1; end
                    if idx <= numel(toks), t(end+1) = toks(idx); idx = idx + 1; end
                end
                jobsOpsCount = jobsOpsCount + 1;
                machines{jobsOpsCount} = m(:).';
                times{jobsOpsCount} = t(:).';
            end
        end
        li = li + 1;
        op_mach{j} = machines;
        op_time{j} = times;
        totalOps = totalOps + jobsOpsCount;
    end

    prob = assemble_prob(op_mach, op_time, numMachines, numJobs, totalOps, fn);

    % Robustness: normalise machine IDs to a 1-based, in-range encoding WITHOUT
    % changing the declared numMachines (so decode's machine bookkeeping stays
    % consistent). Two safe normalisations only:
    %   (a) 0-indexed files (machine IDs start at 0) -> shift everything by +1.
    %   (b) any residual out-of-range ID (shouldn't happen for clean files) ->
    %       clamp into [1, numMachines].
    % Standard 1..numMachines contiguous files are unaffected (no-op). The
    % declared numMachines from the header is ALWAYS preserved. ADDITIVE / safe.
    allM = [];
    for j = 1:numJobs
        for k = 1:numel(op_mach{j})
            allM = [allM, op_mach{j}{k}(:)'];
        end
    end
    if ~isempty(allM)
        um = sort(unique(allM));
        shift = 0;
        if um(1) < 1
            shift = 1 - um(1);   % 0-indexed -> 1-indexed
        end
        if shift ~= 0 || any(um > numMachines)
            for j = 1:numJobs
                for k = 1:numel(op_mach{j})
                    v = op_mach{j}{k} + shift;
                    v = max(1, min(numMachines, v));   % clamp into valid range
                    op_mach{j}{k} = v(:).';
                end
            end
            prob = assemble_prob(op_mach, op_time, numMachines, numJobs, totalOps, fn);
        end
    end
end

function prob = builtin_mk01()
% builtin_mk01  Brandimarte MK01 (10 jobs, 6 machines, 55 operations).
% Each operation is eligible on all 6 machines with the standard processing times.
% 10 jobs x 5 operations = 50 operations total. Best-known makespan (BKS) = 40.
% Source: Brandimarte (1993); widely reproduced in FJSP literature.
    % op_time{j}{k} = processing time on machines 1..6
    T = {
        [5 3 4 2 3 4]; [6 4 3 5 4 5]; [4 5 6 3 5 6]; [3 6 5 4 2 3]; ...
        [5 4 3 6 5 4]; [4 3 4 5 6 5]; [6 4 5 3 4 3]; [5 5 6 4 3 5]; ...
        [3 4 5 6 4 4]; [4 3 4 5 6 3]   % job 10 times on M1..M6
    };
    numJobs = 10; numMachines = 6;
    op_mach = cell(numJobs, 1);
    op_time = cell(numJobs, 1);
    for j = 1:numJobs
        op_mach{j} = cell(1, 5);
        op_time{j} = cell(1, 5);
        for k = 1:5
            op_mach{j}{k} = 1:numMachines;
            op_time{j}{k} = T{j};   % processing times on all 6 eligible machines
        end
    end
    totalOps = sum(cellfun(@numel, op_time));   % 10*5 = 50
    prob = assemble_prob(op_mach, op_time, numMachines, numJobs, totalOps, 'MK01');
    prob.bks = 40;  % best-known makespan for MK01
end

function prob = assemble_prob(op_mach, op_time, numMachines, numJobs, totalOps, src)
% assemble_prob  Convert (op_mach, op_time) cells into the LLMAOO 'prob' structure.
% Mirrors load_data's field set so decode / decode_X / aoo_engine behave identically.
    machW = ones(numMachines, 1);
    nOpPerJob = cellfun(@numel, op_time).';   % row vector, matches load_data

    % Relaxed makespan upper bound (matches load_data): sum of the cheapest eligible
    % processing time per operation, ignoring machine conflicts / precedence.
    mk_ub = 0;
    for j = 1:numJobs
        for k = 1:numel(op_time{j})
            tk = op_time{j}{k};
            assert(isvector(tk) && all(isfinite(tk)) && all(tk > 0), ...
                'assemble_prob: non-positive or illegal op time at job %d op %d', j, k);
            mk_ub = mk_ub + min(tk);
        end
    end

    % Global operation-index maps required by decode_X / decode (jobOf, opOf, opGlobal).
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

    prob = struct();
    prob.nJob = numJobs;
    prob.nOp = totalOps;
    prob.nMachine = numMachines;
    prob.machW = machW;
    prob.op_mach = op_mach;
    prob.op_time = op_time;
    prob.nOpPerJob = nOpPerJob;
    prob.opGlobal = opGlobal;
    prob.jobOf = jobOf;
    prob.opOf = opOf;
    prob.mk_ub = mk_ub;
    % 阶段一：负荷差物理上界（与 load_data 同源，= 全部工序最快工时之和）。
    % 见 load_data.m 同名字段注释；evaluate 缺失 load_ub 时回退 mk_ub（零回归）。
    prob.load_ub = mk_ub;
    prob.name = src;
    prob.has_setup = false;
    prob.has_agv = false;
    prob.has_energy = false;
    prob.has_dynamic = false;
    prob.is_reentrant = false;
    if ~isfield(prob, 'bks'), prob.bks = NaN; end
end
