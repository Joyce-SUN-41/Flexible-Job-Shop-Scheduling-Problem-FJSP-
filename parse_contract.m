%% 解析 LLM 输出：从可能包含 Markdown 代码块的自然语言中提取 JSON 契约
function contract = parse_contract(text)
    contract = struct('heuristics','', 'levy_gain',1.0, 'diff_gain',1.0, ...
                      'explore_bias',1.0, 'ls_mode','CRITICAL_BLOCK', ...
                      'target_machine',-1, 'stagnant',false, ...
                      'diversity','MED', 'action','KEEP', ...
                      'dynamic_strategy','REACTIVE', 'priority','LOAD');
    % Stage8 extension fields (multi-agent contract):
    %   dynamic_strategy : RESERVED 保留字段。动态重调度策略(REACTIVE/PROACTIVE/HYBRID)。
    %                       【当前版本未消费】默认 static 场景主链不读取此字段，避免虚假双引擎声明。
    %   priority         : RESERVED 保留字段。三目标权衡偏好(MAKESPAN/LOAD/ENERGY)。
    %                       【当前版本未消费】evaluate 权重由 cfg.W_MAKESPAN/W_LOAD 控制，
    %                       此字段仅解析存储、不参与搜索，待 Stage8 动态主链接入后启用。
    % 提取第一个 {...} JSON 片段
    s = strfind(text, '{'); e = strfind(text, '}');
    if isempty(s) || isempty(e), return; end
    jsonStr = text(s(1):e(end));
    try
        kv = jsondecode(jsonStr);
        if isfield(kv,'heuristics'), contract.heuristics = kv.heuristics; end
        if isfield(kv,'levy_gain'), contract.levy_gain = clamp(scalar(kv.levy_gain),0.5,2.0); end
        if isfield(kv,'diff_gain'), contract.diff_gain = clamp(scalar(kv.diff_gain),0.5,2.0); end
        if isfield(kv,'explore_bias'), contract.explore_bias = clamp(scalar(kv.explore_bias),0.5,2.0); end
        if isfield(kv,'ls_mode'), contract.ls_mode = upper(kv.ls_mode); end
        if isfield(kv,'target_machine')
            tm = round(scalar(kv.target_machine));
            % 守卫：仅保留非负整数；具体机器编号合法性由下游按 nMachine 判定，
            % 此处不钳制上界以免误改有效值，但保证非有限值回落默认 -1。
            if ~(isfinite(tm) && tm >= 1), tm = -1; end
            contract.target_machine = tm;
        end
        if isfield(kv,'stagnant'), contract.stagnant = logical(scalar(kv.stagnant)); end
        if isfield(kv,'diversity'), contract.diversity = upper(kv.diversity); end
        if isfield(kv,'action'), contract.action = upper(kv.action); end
        if isfield(kv,'dynamic_strategy')
            ds = upper(kv.dynamic_strategy);
            if ismember(ds, {'REACTIVE','PROACTIVE','HYBRID'}), contract.dynamic_strategy = ds; end
        end
        if isfield(kv,'priority')
            pr = upper(kv.priority);
            if ismember(pr, {'MAKESPAN','LOAD','ENERGY'}), contract.priority = pr; end
        end
    catch
        % 解析失败保持默认，不影响 AOO 运行
    end
end

function v = scalar(x)
    if iscell(x), v = x{1}; else v = x; end
    if ~isscalar(v), v = v(1); end
end
function v = clamp(v,lo,hi), v = max(lo, min(hi, v)); end
function s = logical_to_str(b), if b, s='true'; else s='false'; end; end
