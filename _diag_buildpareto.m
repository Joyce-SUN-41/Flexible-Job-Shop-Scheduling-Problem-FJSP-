addpath tests; addpath benchmarks; addpath benchmarks/baselines;
prob = load_data('data.mat');
archive = {struct('OS', ones(1,prob.nOp), 'MS', ones(1,prob.nOp), ...
                  'X', ones(1,2*prob.nOp), 'Z', [0.5, 0.3])};
cfg = llmaoo_config();
p = build_pareto(prob, archive, cfg);
disp('MK='); disp(p.mk);
disp('OBJ3='); disp(p.obj3);
disp('SZ='); disp(size(p.obj3));
