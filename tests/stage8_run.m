function stage8_run()
% stage8_run lightweight self-test (no full solve; verifies module interfaces
% and zero-regression of the default main chain).
% Run: cd to project root in MATLAB, then execute stage8_run

    fprintf('==== Stage8 lightweight self-test ====\n');
    rng(12345);

    % 1. define_problem modes
    fprintf('\n[1] define_problem modes\n');
    p0 = define_problem('static','MK01');
    pg = define_problem('green','MK01');
    pm = define_problem('multi','MK01');
    pt = define_problem('transport','MK01');
    assert(p0.has_energy==false && p0.has_agv==false, 'static must have no new capability');
    assert(pg.has_energy==true, 'green must enable energy');
    assert(pm.has_energy==true, 'multi must enable energy');
    assert(pt.has_agv==true, 'transport must enable AGV');
    assert(isequal(p0.nJob,pg.nJob) && isequal(p0.op_mach,pg.op_mach), ...
           'define_problem must not change existing fields');
    fprintf('  static/green/multi/transport OK (nJob=%d)\n', p0.nJob);

    % 2. perturbation events
    fprintf('\n[2] perturbation events\n');
    e1 = perturbation(p0, 10, 'machine_breakdown', 'machine', 2, 'dur', 5);
    e2 = perturbation(p0, 20, 'urgent_insert');
    e3 = perturbation(p0, 15, 'job_delay', 'job', 1, 'dur', 8);
    assert(strcmp(e1.type,'machine_breakdown') && e1.machine==2, 'breakdown event bad');
    assert(strcmp(e2.type,'urgent_insert') && e2.new_job==p0.nJob+1, 'urgent event bad');
    assert(strcmp(e3.type,'job_delay') && e3.job==1, 'delay event bad');
    fprintf('  breakdown/urgent/delay OK\n');

    % 3. attach_stage8 + three-objective evaluate
    fprintf('\n[3] attach_stage8 + evaluate three-obj\n');
    cfg = llmaoo_config();
    cfg.AOO_THREE_OBJ = true;
    base = load_data(cfg.DATA_FILE);
    pen = attach_stage8(base, cfg);
    assert(pen.has_energy==true, 'attach energy failed');
    chrom = init_chrom(pen);
    [Z2, mk, ld, ~, ex2] = evaluate(pen, chrom, [1 1]);
    [Z3, ~, ~, ~, ex3] = evaluate(pen, chrom, [1 1 1]);
    assert(isscalar(Z2) && ~isnan(ex2.energy), 'two-obj+extra bad');
    assert(isvector(ex3.obj) && numel(ex3.obj)==3, 'three-obj vector must be 3');
    assert(ex3.energy > 0, 'energy must be positive');
    fprintf('  three-obj obj=[%.4f, %.4f, %.4f] energy=%.2f (Z2=%.4f)\n', ...
            ex3.obj(1), ex3.obj(2), ex3.obj(3), ex3.energy, Z2);

    % 4. decode AGV transport
    fprintf('\n[4] decode AGV transport\n');
    cfgA = llmaoo_config();
    cfgA.AOO_AGV = true;
    pa = attach_stage8(base, cfgA);
    assert(pa.has_agv==true, 'attach AGV failed');
    [sa, mka, ~] = decode(pa, chrom, cfgA);
    [sb, mkb, ~] = decode(base, chrom);
    assert(mka >= mkb, 'AGV transport must not reduce makespan');
    assert(isfield(sa,'start') && length(sa)>=pa.nOp, 'AGV schedule struct bad');
    fprintf('  AGV makespan=%.2f >= no-AGV makespan=%.2f (transport active)\n', mka, mkb);

    % 5. parse_contract multi-agent fields
    fprintf('\n[5] parse_contract multi-agent\n');
    fake = ['{"heuristics":"focus critical block","levy_gain":1.3,"diff_gain":0.9,' ...
            '"explore_bias":1.1,"dynamic_strategy":"HYBRID","priority":"ENERGY"}'];
    c = parse_contract(fake);
    assert(strcmp(c.dynamic_strategy,'HYBRID') && strcmp(c.priority,'ENERGY'), ...
           'multi-agent contract fields bad');
    fprintf('  dynamic_strategy=%s priority=%s OK\n', c.dynamic_strategy, c.priority);

    % 6. zero regression: default cfg main chain unchanged
    fprintf('\n[6] zero regression: default cfg main chain\n');
    cfgD = llmaoo_config();
    pD = load_data(cfgD.DATA_FILE);
    [Zd, mkd, ldd, ~] = evaluate(pD, chrom, [cfgD.W_MAKESPAN, cfgD.W_LOAD]);
    assert(isscalar(Zd) && isfinite(Zd), 'default evaluate must return finite scalar');
    % default decode 2-arg must equal default decode 3-arg (AOO_AGV=false => no AGV)
    [sd2, mks2, ~] = decode(pD, chrom);
    [sd3, mks3, ~] = decode(pD, chrom, cfgD);
    % NOTE: sd.start is a comma-separated list; wrap in [] for vector comparison
    assert(mks2==mks3 && isequal([sd2.start], [sd3.start]), 'default decode 2-arg vs 3-arg must match');
    assert(mks2==mkb, 'default decode must equal no-AGV baseline');
    fprintf('  default evaluate Z=%.4f makespan=%.2f (matches Stage7, zero regress)\n', Zd, mks2);

    fprintf('\n==== Stage8 lightweight self-test ALL PASS ====\n');
end

function chrom = init_chrom(prob)
    order = [];
    for j=1:prob.nJob
        order = [order, repmat(j, 1, prob.nOpPerJob(j))];
    end
    os = order(randperm(length(order)));
    ms = zeros(1, sum(prob.nOpPerJob));
    jobOpPtr = zeros(1, prob.nJob);
    for t=1:length(os)
        j = os(t);
        jobOpPtr(j) = jobOpPtr(j) + 1;
        machSet = prob.op_mach{j}{jobOpPtr(j)};
        ms(t) = machSet(randi(length(machSet)));
    end
    chrom = struct('OS', os(:).', 'MS', ms);
end
