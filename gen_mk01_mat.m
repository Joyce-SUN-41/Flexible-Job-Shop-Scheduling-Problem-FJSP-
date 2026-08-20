% gen_mk01_mat  build data_MK01.mat (load_data-compatible) from standard MK01.
addpath('benchmarks');
p = define_problem('static', 'MK01');
operation_time   = p.op_time;
operation_machine= p.op_mach;
num_machine      = p.nMachine;
num_job          = p.nJob;
num_op           = p.nOpPerJob;
machine_weight   = p.machW;
save('data_MK01.mat', 'operation_time', 'operation_machine', 'num_machine', ...
     'num_job', 'num_op', 'machine_weight');
fprintf('MK01_MAT_SAVED nJob=%d nMachine=%d nOp=%d\n', num_job, num_machine, sum(num_op));
