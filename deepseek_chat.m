%% deepseek_chat.m — DeepSeek 大模型客户端（MATLAB 直连 + 离线回退）
% 职责（双引擎之"引擎一"）：作为 FJSP 调度知识中枢。
%   - 联网模式：用 webwrite 调用 DeepSeek OpenAI 兼容 /chat/completions 接口。
%   - 离线模式：未配置 API Key 或调用失败时，返回本地启发式（mock），保证链路可跑。
%   - 缓存：相同 prompt 命中缓存，避免重复计费与延迟。
%
% 设计原则（继承自原始双引擎"优雅降级"哲学）：
%   任何网络异常都降级为本地启发式，绝不抛未处理异常导致整条优化链路崩溃。

function [text, ok, mode, stats] = deepseek_chat(cfg, system_prompt, user_prompt)
    % 输出 mode：'online' 真实联网成功 | 'cached' 命中缓存 | 'offline' 未配钥降级 |
    %            'fallback' 联网失败降级。ok 表示文本是否可作为有效知识消费。
    % stats（可选第四输出）：本次调用累计计数，供实验报告量化 LLM 贡献。
    ok = false;
    text = '';
    mode = 'offline';
    stats = struct('llm_calls', 0, 'llm_cache_hits', 0, 'llm_fallbacks', 0, 'llm_online', 0);

    % --- 计数持久化（跨调用累计，不因函数返回值丢弃而丢失）---
    persistent P;
    if isempty(P), P = struct('calls',0,'hits',0,'fallbacks',0,'online',0); end

    % 支持 deepseek_chat(cfg, [], [], 'reset') 重置计数（供 verify_run 连跑隔离）
    if ischar(system_prompt) && strcmpi(system_prompt, 'reset')
        P = struct('calls',0,'hits',0,'fallbacks',0,'online',0);
        return;
    end
    % 支持 deepseek_chat(cfg, 'stats', '') 只读返回当前累计（不触发任何调用）
    if ischar(system_prompt) && strcmpi(system_prompt, 'stats')
        assign_stats();
        return;
    end

    % --- 1) 缓存命中 ---
    if cfg.LLM_CACHE
        cached = llm_cache('get', user_prompt);
        if ~isempty(cached)
            text = cached; ok = true; mode = 'cached';
            P.hits = P.hits + 1;
            assign_stats(); return;
        end
    end

    % --- 2) 未配置 Key 或显式关闭 -> 本地启发式回退（离线可用，非故障）---
    if ~cfg.LLM_ENABLE || isempty(cfg.DEEPSEEK_API_KEY)
        text = local_heuristic(user_prompt);
        ok = true; mode = 'offline';  % 视为"成功"（离线可用）
        % SAFE FIX (2026-08-13): do NOT cache offline heuristic text. Caching it would
        % let a later ONLINE run hit the cache and silently return offline text as
        % 'cached', defeating honest online-gain measurement (stage2 ablation).
        assign_stats(); return;
    end

    % --- 3) 联网调用 DeepSeek ---
    P.calls = P.calls + 1;           % 阶段3：真实联网调用计数（不含缓存/离线）
    try
        options = weboptions('ContentType','json','Timeout',cfg.LLM_TIMEOUT_SEC, ...
                              'RequestMethod','post','ArrayFormat','json');
        options.HeaderFields = {'Authorization', ['Bearer ', cfg.DEEPSEEK_API_KEY]; ...
                                'Content-Type', 'application/json'};
        body = struct('model', cfg.DEEPSEEK_MODEL, ...
                      'messages', {[ struct('role','system','content',system_prompt); ...
                                     struct('role','user','content',user_prompt) ]}, ...
                      'max_tokens', cfg.LLM_MAX_TOKENS, ...
                      'temperature', cfg.LLM_TEMPERATURE, ...
                      'stream', false);
        resp = webwrite(cfg.DEEPSEEK_API_URL, body, options);
        % 阶段3：HTTP 状态码校验（webwrite 成功才到这步；额外校验响应是否被限流/错误包装）
        if isfield(resp,'error')
            % DeepSeek 以 JSON {error: {...}} 返回错误（如 401/429），非异常但需降级
            emsg = '';
            if isfield(resp.error,'message'), emsg = resp.error.message; end
            fprintf('  [LLM] DeepSeek 返回错误对象（可能为 401/429 限流）: %s，降级本地启发式。\n', ...
                emsg);
            text = local_heuristic(user_prompt); ok = true; mode = 'fallback';
            P.fallbacks = P.fallbacks + 1;
            % Do NOT cache fallback text (would poison a later honest online run).
            assign_stats(); return;
        end
        if isfield(resp,'choices') && numel(resp.choices)>=1 && ...
           isfield(resp.choices(1),'message') && isfield(resp.choices(1).message,'content')
            text = resp.choices(1).message.content;
            ok = true; mode = 'online';
            P.online = P.online + 1;
            if cfg.LLM_CACHE, llm_cache('put', user_prompt, text); end
        else
            % 响应结构异常：降级本地启发式，标记 fallback 以便调用方观测
            text = local_heuristic(user_prompt); ok = true; mode = 'fallback';
            P.fallbacks = P.fallbacks + 1;
            fprintf('  [LLM] DeepSeek 响应结构异常（无 choices.message.content），降级本地启发式。\n');
            % Do NOT cache fallback text (would poison a later honest online run).
        end
    catch ME
        % 任何异常（超时/鉴权/网络）一律降级本地启发式，不中断优化
        fprintf('  [LLM] DeepSeek 调用失败，降级本地启发式: %s\n', ME.message);
        text = local_heuristic(user_prompt);
        ok = true; mode = 'fallback';
        P.fallbacks = P.fallbacks + 1;
        % Do NOT cache fallback text (would poison a later honest online run).
    end
    assign_stats();

    % 嵌套函数：把持久计数复制到本次输出 stats，保持函数单出口清晰
    function assign_stats()
        stats.llm_calls      = P.calls;
        stats.llm_cache_hits = P.hits;
        stats.llm_fallbacks  = P.fallbacks;
        stats.llm_online     = P.online;
    end
end

%% 本地启发式回退：从 user_prompt 中解析出的统计信息生成通用调度建议
% 这里不依赖真实 LLM，给出"负荷均衡优先"的稳健默认规则，
% 保证在无网络/无 Key 时 AOO 仍能获得有效（即便朴素）的知识信号。
function h = local_heuristic(user_prompt)
    % 默认启发式：若检测到存在高负载机器，偏向把长工序移到低负载机器
    if contains(user_prompt, '瓶颈') || contains(user_prompt, 'bottleneck') ...
       || contains(user_prompt, '负荷')
        h = '优先将关键路径上工时最长的工序分配到当前累积负荷最低的机器；' ...
          + '对高负载机器上的非关键工序，尝试迁移至可选机器中负荷次低者。';
    elseif contains(user_prompt, '停滞') || contains(user_prompt, 'stagnat')
        h = '当前搜索疑似停滞：建议提高 Levy 飞行步长以加强全局探索，' ...
          + '并增加机器重指派变异概率以跳出局部最优。';
    else
        h = '维持负荷均衡偏好：在不破坏工序优先级约束下，' ...
          + '优先降低最大机器负荷。';
    end
end

%% 极简文件缓存（避免重复联网）
function val = llm_cache(op, key, val)
    persistent C;
    if isempty(C), C = containers.Map('KeyType','char','ValueType','any'); end
    if strcmpi(op,'get')
        if C.isKey(key), val = C(key); else val = ''; end
    else
        C(key) = val;
    end
end
