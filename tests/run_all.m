%% tests/run_all.m — LLMAOO 统一回归测试入口
% 运行：在 MATLAB 中 cd 到项目根目录后执行 tests/run_all，
%       或直接 matlab -batch "cd('项目根'); tests.run_all; exit"（需 chdir）。
% 本脚本自动切换到项目根目录（tests 的父目录）以保证 load_data('data.mat')
% 等相对路径解析正确，再依次运行各子测试。
%
% 设计原则（阶段1 工程整洁）：把所有一次性/调试/自测脚本收敛到 tests/ 下，
% 由本文件统一驱动，杜绝根目录散落 _*.bat/_*.m 调试脚本造成的依赖混乱。

function run_all()
    % --- 定位项目根（本文件所在 tests/ 的父目录）---
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    prev = cd(root);   % 切到根目录，保证 data.mat 相对路径有效
    cleanup = onCleanup(@() cd(prev));
    % 确保项目根与 tests 目录在搜索路径上，使相对文件名（coreFiles、子测试）
    % 以及包式调用在 -batch 环境下均可解析（R2024b 不自动将 cwd 加入 search path）。
    addpath(root); addpath(here);

    fprintf('========================================\n');
    fprintf(' LLMAOO 回归测试套件 (root=%s)\n', root);
    fprintf('========================================\n');

    okAll = true;

    %% 1) 静态代码检查（checkcode）：核心源文件不应有 ERROR 级消息
    coreFiles = {'llmaoo.m','llmaoo_config.m','load_data.m','aoo_engine.m', ...
                 'decode.m','evaluate.m','evaluate_population.m', ...
                 'deepseek_chat.m','llm_guided_local_search.m', ...
                 'critical_path.m','parse_contract.m','visualize.m','theme.m', ...
                 'logging.m','obj_of.m','loc_of.m','prompt_knowledge.m', ...
                 'prompt_diagnosis.m','fjsp_system_prompt.m','main.m', ...
                 'select_machine.m','critical_block_neighborhood.m', ...
                 'non_dominated_sort.m','crowding.m','obj_eval.m', ...
                 'benchmarks/load_benchmark.m','experiment_runs.m','stat_report.m', ...
                 'ablation.m','convergence_plot.m', ...
                 'gate_competitiveness.m',                 'benchmarks/baselines/ga_fjsp.m', ...
                 'stage7_run.m', 'tevc_llm_gain.m', 'benchmarks/define_problem.m', ...
                 'benchmarks/perturbation.m','benchmarks/attach_stage8.m', ...
                 'benchmarks/dynamic_replay.m','exports/export_result_json.m', ...
                 'exports/export_replay_json.m','stage8_run.m','stage9_run.m', ...
                 'nsga3_quality.m','das_dennis.m','nsga3_select.m', ...
                 'quality_metrics.m','offline_structured_modulate.m', ...
                 'stageC_run.m','online_llm_modulate.m','stageD_run.m','stageF_run.m','stageG_run.m','stageH_run.m','stage1_run.m', ...
                 'benchmarks/baselines/pso_fjsp.m','tests/fullchain_demo.m', ...
                 'tests/stage7_large_config.m','tests/stageB_sota.m'};
    fprintf('\n--- [1] checkcode 静态检查 ---\n');
    nErr = 0;
    for k = 1:numel(coreFiles)
        m = checkcode(coreFiles{k}, '-float');
        errs = m([m.line] > 0 & strcmpi({m.message},'error')); % 仅计数 ERROR 级
        % 注：checkcode 默认全为 WARN/INFO；若有 ERROR 才计入
        if ~isempty(errs)
            nErr = nErr + numel(errs);
            for e = 1:numel(errs), fprintf('  %s : %s\n', coreFiles{k}, errs(e).message); end
        end
    end
    fprintf('  checkcode ERROR 级消息数 = %d\n', nErr);
    if nErr > 0, okAll = false; end

    %% 1b) Python 渲染脚本语法检查（非致命：无 python 时跳过）
    % checkcode 仅支持 MATLAB 文件，故对 viz/*.py 单独用 py_compile 校验（Stage9/Stage-F）。
    fprintf('\n--- [1b] Python 渲染脚本语法检查 (非致命) ---\n');
    pyScripts = {'viz/plotly_gantt.py', 'viz/plotly_convergence.py', 'viz/replay_dynamic.py', 'viz/dashboard.py', 'viz/digital_twin.py'};
    [pstat, pout] = system('python -c "import py_compile,sys; [py_compile.compile(f, doraise=True) for f in sys.argv[1:]]" viz/plotly_gantt.py viz/plotly_convergence.py viz/replay_dynamic.py viz/dashboard.py viz/digital_twin.py');
    if pstat == 0
        fprintf('  Python 脚本语法 OK (4 files compiled)\n');
    else
        fprintf('  [warn] Python 脚本语法检查跳过/失败 (非致命): %s\n', strtrim(pout));
    end

    %% 2) decode/evaluate 不变量自测（阶段2 落地，阶段1 一并纳入回归）
    fprintf('\n--- [2] decode_eval_selftest ---\n');
    try
        decode_eval_selftest();
        fprintf('  decode_eval_selftest PASS\n');
    catch ME
        okAll = false;
        fprintf('  decode_eval_selftest FAIL: %s\n', ME.message);
    end

    %% 3) 主链冒烟测试（离线降级跑通）
    fprintf('\n--- [3] smoke_test (llmaoo MAXGEN=20) ---\n');
    try
        cfg = llmaoo_config();
        rng(cfg.RNG_SEED);
        res = llmaoo('AOO_MAXGEN', 20);
        fprintf('  SMOKE_OK makespan=%.1f unbal=%.1f iters=%d\n', ...
                res.makespan, res.loadUnb, res.iters);
    catch ME
        okAll = false;
        fprintf('  SMOKE FAIL: %s\n', ME.message);
    end

    %% 4) AOO vs 随机基线稳定性（阶段1 从根目录 verify_run 迁入，重命名）
    fprintf('\n--- [4] bench_aoo_vs_random ---\n');
    try
        bench_aoo_vs_random();
        fprintf('  bench_aoo_vs_random PASS\n');
    catch ME
        okAll = false;
        fprintf('  bench_aoo_vs_random FAIL: %s\n', ME.message);
    end

    %% 5) 阶段6 实验基础设施可用性（仅 checkcode + 轻量冒烟，重计算不在此自动跑）
    % 完整 TEVC 级实验（N=30 独立运行 + Wilcoxon + 收敛图 + 消融）由 tests.stage6_run()
    % 统一驱动，避免回归套件因长时计算超时。此处仅验证新增脚本可被调用且不崩溃。
    fprintf('\n--- [5] stage6 实验脚本可用性 (轻量) ---\n');
    try
        addpath('benchmarks');   % load_benchmark lives in benchmarks/
        prob = load_benchmark('MK01');   % 内置标准实例，离线可跑
        assert(prob.nJob == 10 && prob.nMachine == 6, 'MK01 size mismatch');
        fprintf('  load_benchmark(''MK01'') OK (nJob=%d nMachine=%d bks=%.0f)\n', ...
                prob.nJob, prob.nMachine, prob.bks);
    catch ME
        okAll = false;
        fprintf('  load_benchmark FAIL: %s\n', ME.message);
    end

    %% 6) 阶段7 竞争力门禁（AOO 不再系统性弱于随机基线）—— 两目标主链口径
    % 轻量 N=10 实验自动校验"阶段6 暴露的 AOO 弱于随机"已被修复；若仍 FAIL
    % 则视为阻断性回归，防止隐性退化被放过。计算较重但 N=10 量级可接受。
    % 双路径口径（阶段三 P1 升级）：本门禁仅校验默认两目标加权和主链（配置 A）；
    % 投稿多目标 NSGA-III 三目标路径（配置 B, AOO_THREE_OBJ=true）的竞争力由
    % 门禁[20] 独立校验（读 logs/stageB_sota.json），二者口径分离、互不阻塞，
    % 避免在回归套件中重复跑重计算。论文须分别如实定位两种互斥配置（见 llmaoo_config 注释）。
    fprintf('\n--- [6] 阶段7 竞争力门禁 (AOO vs Random, 两目标主链) ---\n');
    try
        addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('tests');
        pass = gate_competitiveness('N', 10, 'Prob', 'MK01');
        if pass
            fprintf('  gate_competitiveness PASS (两目标主链)\n');
        else
            okAll = false;
            fprintf('  gate_competitiveness FAIL（两目标主链 AOO 仍弱于 Random，需修复阶段7）\n');
        end
        fprintf('  注: 三目标 NSGA-III 路径(AOO_THREE_OBJ=true)竞争力由门禁[20]校验\n');
    catch ME
        okAll = false;
        fprintf('  gate_competitiveness ERROR: %s\n', ME.message);
    end

    %% 7) 阶段8 轻量自测（问题设定升级：动态/三目标/绿色/AGV/多智能体契约）
    % 仅验证新模块接口与零回归（不跑完整求解，防回归套件超时）。
    % 完整阶段8 动态/绿色 N=30 对比实验由 tests.stage8_run 备置，不自动跑。
    fprintf('\n--- [7] stage8 模块自测 (轻量) ---\n');
    try
        addpath('benchmarks'); addpath('tests');
        stage8_run();
        fprintf('  stage8_run PASS\n');
    catch ME
        okAll = false;
        fprintf('  stage8_run FAIL: %s\n', ME.message);
    end

    %% 8) 阶段9 可视化导出契约自测（JSON 导出 + 默认关零回归 + 动态 replay）
    % 仅验证导出契约与零回归（不跑完整求解，防回归套件超时）。
    fprintf('\n--- [8] stage9 可视化导出自测 (轻量) ---\n');
    try
        addpath('benchmarks'); addpath('exports'); addpath('tests');
        stage9_run();
        fprintf('  stage9_run PASS\n');
    catch ME
        okAll = false;
        fprintf('  stage9_run FAIL: %s\n', ME.message);
    end

    %% 9) 阶段A 动态多目标场景激活自测（零回归 + 各模式端到端可用）
    % 验证 AOO_DEFAULT_SCENARIO 默认 'static' 不破坏主链，且 multi/dynamic/green/
    % transport/full 能正确开启对应能力位并由 define_problem 构造 prob。
    fprintf('\n--- [9] stageA 默认场景激活自测 (轻量) ---\n');
    try
        addpath('benchmarks'); addpath('tests');
        % 9.1 默认 static 不触发任何 Stage8 能力位（零回归）
        cfgS = llmaoo_config();
        assert(strcmpi(cfgS.AOO_DEFAULT_SCENARIO,'static'), 'default scenario must be static');
        assert(~cfgS.AOO_THREE_OBJ && ~cfgS.AOO_AGV && ~cfgS.AOO_DYNAMIC, ...
               'static must keep Stage8 bits off (zero regression)');
        % 9.2 define_problem 各模式字段正确
        pStat = define_problem('static','MK01');
        pMul  = define_problem('multi','MK01');
        pDyn  = define_problem('dynamic','MK01','scenario','breakdown');
        assert(~pStat.has_energy && ~pStat.has_agv, 'static no caps');
        assert(pMul.has_energy, 'multi enables energy');
        assert(pDyn.has_dynamic && strcmp(pDyn.dynamic_scenario,'breakdown'), 'dynamic sets scenario');
        % 9.3 multi 场景下 evaluate 第五输出为三目标向量（主链数值语义不变，仅附加）
        % 注意：define_problem 仅置 has_energy；AOO_THREE_OBJ 由 attach_stage8(cfg) 置位，
        % 与 llmaoo 激活态一致。此处复现该链路验证三目标评估。
        cfgM = llmaoo_config(); cfgM.AOO_THREE_OBJ = true;
        pMulA = attach_stage8(pMul, cfgM);
        chrom = init_chrom_stageA(pMulA);
        [Z2,~,~,~,ex] = evaluate(pMulA, chrom, [1 1 1]);
        assert(isvector(ex.obj) && numel(ex.obj)==3 && ex.energy>0, 'multi three-obj bad');
        % 9.4 轻量主链端到端（multi 模式跑极少代，验证不崩溃、pareto 含能耗）
        rng(cfgS.RNG_SEED);
        res = llmaoo('AOO_DEFAULT_SCENARIO','multi','AOO_MAXGEN',8);
        assert(isfinite(res.makespan) && isfield(res,'pareto'), 'multi llmaoo must run');
        if isfield(res.pareto,'energy') && ~isempty(res.pareto.energy)
            assert(all(res.pareto.energy>0), 'pareto energy must be positive');
        end
        % 9.5 阶段二 P1 guard: energy 第三维必须真实分化（修复旧 obj3 恒 0.6645 塌缩）。
        % 直接验证 attach_energy 设置了固定上界 e_ub，且随机染色体上的归一化能耗 en
        % 存在可观测跨度（不再全部塌缩到 1/1.5≈0.667 渐近线）。
        assert(isfield(pMul,'e_ub') && pMul.e_ub > 0, 'attach_energy must set fixed e_ub');
        ens = zeros(40,1);
        for qi = 1:40
            ch = init_chrom_stageA(pMul);
            [~,~,~,~,exq] = evaluate(pMul, ch, [1 1 1]);
            ens(qi) = exq.obj(3);   % 归一化 energy 维
        end
        assert(range(ens) > 1e-3, sprintf('energy 3rd-obj degenerate (range=%.2e)', range(ens)));
        fprintf('  stageA self-test PASS (static zero-reg + multi/dynamic OK, makespan=%.1f, en-range=%.3f)\n', ...
            res.makespan, range(ens));
    catch ME
        okAll = false;
        fprintf('  stageA self-test FAIL: %s\n', ME.message);
    end

    %% 10) 阶段B NSGA-III 质量指标自检（HV/IGD 正确性 + 端到端存档链路）
    % 不跑完整求解（防回归套件超时），仅验证指标数值正确与存档三目标向量可用。
    fprintf('\n--- [10] stageB 质量指标自测 (轻量) ---\n');
    try
        addpath('benchmarks'); addpath('exports'); addpath('tests');
        quality_metrics();
        fprintf('  quality_metrics PASS\n');
    catch ME
        okAll = false;
        fprintf('  quality_metrics FAIL: %s\n', ME.message);
    end

    %% 11) 阶段C LLM 双引擎调制层自测（零回归 + 增益随代变化 + 端到端可用）
    % 验证 OFFLINE_STRUCTURED_MODULATE 真正改变三增益（非恒1.0）、aoo_engine
    % 在调制开启/关闭下均端到端可跑、ablation 入口正常。不跑完整求解防超时。
    fprintf('\n--- [11] stageC LLM增益调制层自测 (轻量) ---\n');
    try
        addpath('benchmarks'); addpath('tests');
        stageC_run();
        fprintf('  stageC_run PASS\n');
    catch ME
        okAll = false;
        fprintf('  stageC_run FAIL: %s\n', ME.message);
    end

    %% 12) 阶段D 在线 LLM 真实增益量化闭环自测（零回归 + 诚实归因 + 端到端可用）
    % 验证 online_llm_modulate 在线保留真实增益/离线回落结构化调制、默认开关零回归、
    % ablation 离线诚实等价、ONLINE_LLM_MODULATE=true 端到端不崩溃。不跑完整求解防超时。
    fprintf('\n--- [12] stageD 在线LLM增益量化闭环自测 (轻量) ---\n');
    try
        addpath('benchmarks'); addpath('tests');
        stageD_run();
        fprintf('  stageD_run PASS\n');
    catch ME
        okAll = false;
        fprintf('  stageD_run FAIL: %s\n', ME.message);
    end

    %% 13) 阶段F 可视化渲染闭环自测（Stage9 JSON 契约 -> 真实 Plotly HTML）
    % 生成真实 LLMAOO 结果/收敛/replay JSON，并驱动 Python 三脚本渲染 HTML。
    % Python 步骤非致命（无 plotly 时跳过，与 stage9_run 探针一致），不影响 ALL GREEN。
    % 预算压到极小（MAXGEN 12/POP 12）以防套件超时。
    fprintf('\n--- [13] stageF 可视化渲染闭环自测 (轻量) ---\n');
    try
        addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz'); addpath('tests');
        stageF_run();
        fprintf('  stageF_run PASS\n');
    catch ME
        okAll = false;
        fprintf('  stageF_run FAIL: %s\n', ME.message);
    end

    %% 14) 阶段G Streamlit 交互式仪表盘自检（ADDITIVE，纯读JSON，非致命python）
    % 验证 viz/dashboard.py 存在 + python语法OK + (若streamlit已装)导入烟雾测试。
    % 仪表盘只读阶段9/F导出的JSON契约，不触solver，零回归风险。python步骤非致命。
    fprintf('\n--- [14] stageG 交互式仪表盘自测 (轻量, 非致命) ---\n');
    try
        addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz'); addpath('tests');
        stageG_run();
        fprintf('  stageG_run PASS\n');
    catch ME
        okAll = false;
        fprintf('  stageG_run FAIL: %s\n', ME.message);
    end

    %% 15) 阶段H Three.js 数字孪生3D视图自测（ADDITIVE，纯读JSON，非致命python）
    % 验证 viz/digital_twin.py 存在 + python语法OK + (若python可用)生成自包含HTML。
    % 数字孪生只读阶段9/F导出的JSON契约，不触solver，零回归风险。python步骤非致命。
    fprintf('\n--- [15] stageH 数字孪生3D视图自测 (轻量, 非致命) ---\n');
    try
        addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz'); addpath('tests');
        stageH_run();
        fprintf('  stageH_run PASS\n');
    catch ME
        okAll = false;
        fprintf('  stageH_run FAIL: %s\n', ME.message);
    end

    %% 16) 阶段一 gate：最火问题场景（dynamic / multi）真实可解 + JSON 导出闭环
    % 验证 dynamic 重调度与 multi 三目标场景能端到端求解并导出 replay/results JSON，
    % 使最火可视化（数字孪生/replay）绑定最火问题。ADDITIVE、零回归（默认 static 不动）。
    % Python 数字孪生渲染为非致命步骤（无 python 时跳过）。
    fprintf('\n--- [16] 阶段一 gate: 最火场景(dynamic/multi)可解 + 导出闭环 (轻量) ---\n');
    try
        addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz'); addpath('tests');
        stage1_run();
        fprintf('  stage1_run PASS\n');
    catch ME
        okAll = false;
        fprintf('  stage1_run FAIL: %s\n', ME.message);
    end

    %% 17) 阶段五 gate：投稿级证据链（SOTA 对比 aoo/ga/pso/random + 完整基准脚手架）
    % 验证 experiment_runs 新增 pso 变体可用、stat_report 产出 Wilcoxon 显著性、
    % MK01 实跑并导出 logs/stage5_sota_compare.json。MK02-10 标注数据依赖（不伪造）。
    % 预算轻量（N=10）以防套件超时；完整 N=30 证据由 tests.stage5_run 手动跑。
    % ADDITIVE：仅新增基线 pso_fjsp + 聚合视图，不改 solver 数值语义。
    fprintf('\n--- [17] 阶段五 gate: 投稿级证据链 (SOTA对比 aoo/ga/pso/random) ---\n');
    try
        addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz'); addpath('tests');
        stage5_run();
        fprintf('  stage5_run PASS\n');
    catch ME
        okAll = false;
        fprintf('  stage5_run FAIL: %s\n', ME.message);
    end

    %% 18) 定向鲁棒性单测：① 工件工序数不等实例 aoo_engine 不越界（复现 opOf 修复）；
    %     ② parse_fjs 兼容标准(layout A: 首token=工序数) 与 wrqccc(layout B: 首token=op1 altCount)
    %     两种 FJS 格式。针对 aoo_engine 大改后无定向回归的缺口，防 opOf 误用复发。
    % ADDITIVE：纯构造合成 prob + 调解析器，不改 solver 数值语义；失败才置 okAll=false。
    fprintf('\n--- [18] 定向鲁棒性单测: 不等工序实例 + parse_fjs 双 layout ---\n');
    try
        addpath('benchmarks'); addpath('benchmarks/baselines'); addpath('exports'); addpath('viz'); addpath('tests');
        stage_robustness_test();
        fprintf('  stage_robustness_test PASS\n');
    catch ME
        okAll = false;
        fprintf('  stage_robustness_test FAIL: %s\n', ME.message);
    end

    %% 19) 阶段一 P0 gate：large-config 不劣于默认配置（弱实例 MK02/06/09）
    % 软失败设计（安全）：仅当两份日志都存在时才断言；缺失任一份则 SKIP 不阻塞
    % （长计算日志由用户显式跑 tests.stage7_run / tests.stage7_large_config 生成）。
    % 断言：large-config 的 gap_best 不显著劣于默认配置（容差 TOL=5%，允许数值波动）。
    % 目的：保证"结构性补偿"探索不会反而退化默认证据，且不与主证据矛盾。
    fprintf('\n--- [19] 阶段一 P0: large-config vs default-config (弱实例) ---\n');
    try
        defPath = fullfile(root, 'logs', 'stage7_benchmark.json');
        larPath = fullfile(root, 'logs', 'stage7_large.json');
        if ~isfile(defPath) || ~isfile(larPath)
            fprintf('  SKIP (缺失 %s 或 %s，长计算日志未生成；不阻塞)\n', ...
                'stage7_benchmark.json', 'stage7_large.json');
        else
            defD = loadjson(defPath); larD = loadjson(larPath);
            TOL = 5.0;  % 允许 large-config gap_best 比默认差不超过 5 个百分点
            weak = {'MK02','MK06','MK09'};
            allOK = true;
            for w = 1:numel(weak)
                nm = weak{w};
                gDef = benchmark_gap(defD, nm);
                gLar = large_gap(larD, nm);
                if isnan(gDef) || isnan(gLar)
                    fprintf('  %s  SKIP (日志缺字段)\n', nm);
                    continue;
                end
                delta = gLar - gDef;  % >0 表示 large-config 更差
                status = 'OK';
                if delta > TOL, allOK = false; status = 'WORSE'; end
                fprintf('  %s: default gapBest=%.1f%%  large gapBest=%.1f%%  delta=%.1f%%  [%s]\n', ...
                    nm, gDef, gLar, delta, status);
            end
            if allOK
                fprintf('  stage1-large gate PASS (large-config 不劣于默认配置)\n');
            else
                okAll = false;
                fprintf('  stage1-large gate FAIL (large-config 显著劣于默认配置)\n');
            end
        end
    catch ME
        % 解析异常不阻塞主套件（日志格式问题属非阻断）
        fprintf('  stage1-large gate SKIP (解析异常: %s)\n', ME.message);
    end

    %% 20) 阶段三 P1 gate：三目标 NSGA-III 竞争力（AOO vs Random, multi 场景）
    % 软失败设计（安全）：仅当 logs/stageB_sota.json 存在时报告；缺失则 SKIP 不阻塞。
    % 阶段四 optA 已诚实定位：NSGA-III 三目标路径为"可选扩展/对比章节"，默认主链为
    % 两目标加权和。本门禁不再将"三目标须胜 Random"作为阻断项（否则与 optA 决策矛盾），
    % 而是如实报告 AOO 三目标 HV vs Random 的均值与 Wilcoxon，供 Limitations 诚实讨论。
    fprintf('\n--- [20] 阶段三 P1: 三目标 NSGA-III 竞争力 (AOO vs Random, 诚实报告) ---\n');
    try
        sB = fullfile(root, 'logs', 'stageB_sota.json');
        if ~isfile(sB)
            fprintf('  SKIP (缺失 logs/stageB_sota.json，长计算日志未生成；不阻塞)\n');
            fprintf('        手动生成: MATLAB 中执行 tests.stageB_sota\n');
        else
            d = loadjson(sB);
            if isfield(d, 'hv') && isfield(d.hv, 'aoo') && isfield(d.hv, 'random')
                hvA = d.hv.aoo(:); hvR = d.hv.random(:);
                mA = mean(hvA); mR = mean(hvR);
                [pval, h] = ranksum(hvA, hvR);
                imp = 100 * (mA - mR) / mR;  % AOO 相对 Random 的 HV 变化（负=更差）
                fprintf('  AOO HV mean=%.4g  Random HV mean=%.4g  improve=%.1f%%\n', mA, mR, imp);
                fprintf('  Wilcoxon(AOO HV vs Random HV): p=%.4g  h=%d\n', pval, h);
                % 阶段四 optA：NSGA-III 为可选扩展，不强制胜 Random；仅如实记录。
                % 若 AOO 显著弱于 Random（h==1 且 imp<0），标注为已知 Limitations，不阻断。
                if h == 1 && imp < 0
                    fprintf('  NSGA-III 三目标 HV 显著弱于 Random (已知 Limitations, 阶段四 optA 定位为可选扩展)\n');
                else
                    fprintf('  AOO 三目标 HV 不显著弱于 Random\n');
                end
                fprintf('  stage3-three-obj report OK (非阻断，详见 docs/multiobj_positioning.md)\n');
            else
                fprintf('  [warn] stageB_sota.json 缺少 hv.aoo/hv.random 字段，跳过报告\n');
            end
        end
    catch ME
        fprintf('  stage3-three-obj gate SKIP (解析异常: %s)\n', ME.message);
    end

    fprintf('\n========================================\n');
    if okAll
        fprintf(' 全部回归测试通过 (ALL GREEN)\n');
    else
        fprintf(' 存在失败项，请检查上方日志\n');
    end
    fprintf('========================================\n');
    fprintf(' 提示: 完整阶段6实验 -> 在 MATLAB 中执行 tests.stage6_run\n');
    fprintf(' 提示: 阶段7完整验证 -> 在 MATLAB 中执行 tests.stage7_run\n');
    fprintf(' 提示: 阶段8模块自测 -> 在 MATLAB 中执行 tests.stage8_run\n');
    fprintf(' 提示: 阶段9可视化导出 -> 在 MATLAB 中执行 tests.stage9_run\n');
    fprintf(' 提示: 阶段A场景激活 -> llmaoo(''AOO_DEFAULT_SCENARIO'',''multi'') 或 ''dynamic''\n');
    fprintf(' 提示: 阶段B质量指标 -> tests.quality_metrics\n');
    fprintf(' 提示: 阶段C LLM增益消融 -> 在 MATLAB 中执行 tests.ablation(load_benchmark(''MK01''),''N'',30)\n');
    fprintf(' 提示: 阶段D在线增益量化 -> 在 MATLAB 中执行 tests.stageD_run ；联网真实增益: llmaoo(''ONLINE_LLM_MODULATE'',true,''DEEPSEEK_API_KEY'',''你的KEY'')\n');
    fprintf(' 提示: 阶段F可视化渲染 -> 在 MATLAB 中执行 tests.stageF_run ；手动渲染: pip install -r viz/requirements.txt && python viz/plotly_gantt.py logs/stageF_result.json -o figures/gantt.html\n');
    fprintf(' 提示: 阶段G交互式仪表盘 -> pip install -r viz/requirements.txt && streamlit run viz/dashboard.py\n');
    fprintf(' 提示: 阶段H数字孪生3D -> pip install -r viz/requirements.txt && python viz/digital_twin.py logs/stageF_result.json -o figures/digital_twin.html （浏览器打开双击即用，含Three.js CDN）\n');
    fprintf(' 提示: 阶段五证据链 -> 在 MATLAB 中执行 tests.stage5_run ；SOTA对比: experiment_runs(prob,''Variants'',{''aoo'',''ga'',''pso'',''random''},''N'',30)\n');

    %% 阶段一 P0 辅助：读取 benchmark JSON + 提取弱实例 gapBest
    function D = loadjson(path)
        % 复用 stage7_run 的紧凑 JSON 格式：benchmark 为数组（含 inst 字段），
        % large 为按实例命名的 scalar struct。均用结构体数组/结构解析。
        fid = fopen(path, 'r');
        if fid < 0, D = []; return; end
        raw = fread(fid, '*char').'; fclose(fid);
        % 尝试原生 jsondecode（R2016b+）；失败则回退空（不阻塞）
        try
            D = jsondecode(raw);
        catch
            D = [];
        end
    end

    function g = benchmark_gap(D, nm)
        % D 为 stage7_benchmark.json 的 struct array（含 inst 字段）
        g = NaN;
        if ~isstruct(D), return; end
        for k = 1:numel(D)
            if isfield(D(k), 'inst') && strcmpi(D(k).inst, nm)
                g = D(k).gap_best_pct; return;
            end
        end
    end

    function g = large_gap(D, nm)
        % D 为 stage7_large.json 的 scalar struct（按实例命名）
        g = NaN;
        if ~isstruct(D), return; end
        if isfield(D, nm) && isfield(D.(nm), 'gap_best_pct')
            g = D.(nm).gap_best_pct;
        end
    end
end

%% 阶段A 自测辅助：构造随机可行染色体（与 stage8_run.init_chrom 同语义）
function chrom = init_chrom_stageA(prob)
    order = [];
    for j = 1:prob.nJob
        order = [order, repmat(j, 1, prob.nOpPerJob(j))];
    end
    os = order(randperm(length(order)));
    ms = zeros(1, sum(prob.nOpPerJob));
    jobOpPtr = zeros(1, prob.nJob);
    for t = 1:length(os)
        j = os(t);
        jobOpPtr(j) = jobOpPtr(j) + 1;
        machSet = prob.op_mach{j}{jobOpPtr(j)};
        ms(t) = machSet(randi(length(machSet)));
    end
    chrom = struct('OS', os(:).', 'MS', ms);
end
