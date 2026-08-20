%% logging.m — 轻量统一日志封装（阶段3：可观测性完善）
% 提供 log(msg, level) 同时写控制台（fprintf）与 logs/run_<timestamp>.log 文件。
% 设计目标：让 verify_run / diag_run / llmaoo 的逐 run 输出可结构化留存，
%           供阶段5/6 的统计实验与日志审计使用；不影响离线求解性能（默认开文件）。
%
% 用法：
%   logging('init')                       % 新建本次运行的日志文件（在 logs/ 下）
%   logging('Hello, run started')         % 默认 level='INFO'
%   logging('warning: stale', 'WARN')     % 指定级别
%   logging('done', 'INFO')
% 也可： [msg, level] 形式调用；不传 level 时默认为 INFO。
%
% 线程安全说明：MATLAB 单线程执行优化循环，无需额外锁；parfor 下日志文件并发
% 写入风险由 evaluate_population 当前默认串行规避（阶段4 启用并行时再考虑 labindex 分片）。

function logging(varargin)
    persistent LOGFH;          % 当前打开的日志文件句柄
    persistent TS;             % 本次运行时间戳字符串

    % ---- 初始化：新建日志文件 ----
    if nargin >= 1 && ischar(varargin{1}) && strcmpi(varargin{1}, 'init')
        if ~isempty(LOGFH) && LOGFH > 0, fclose(LOGFH); end
        if isempty(TS)
            TS = datestr(now, 'yyyy-mm-dd_HHMMSS');
        end
        % 确保 logs/ 目录存在
        if ~exist('logs', 'dir'), mkdir('logs'); end
        fn = fullfile('logs', ['run_', TS, '.log']);
        LOGFH = fopen(fn, 'a', 'n', 'UTF-8');
        fprintf('[LOG] 本次运行日志 -> %s\n', fn);
        return;
    end

    % ---- 解析参数 ----
    if nargin < 1, return; end
    msg = varargin{1};
    level = 'INFO';
    if nargin >= 2 && ischar(varargin{2})
        level = upper(varargin{2});
    end

    % 时间戳（精确到秒）
    tstr = datestr(now, 'HH:MM:SS');

    % ---- 控制台 + 文件双写 ----
    line = sprintf('[%s][%s] %s\n', tstr, level, msg);
    fprintf('%s', line);
    if ~isempty(LOGFH) && LOGFH > 0
        fwrite(LOGFH, line, 'char');
        % 关键节点 flush，避免进程异常退出丢失尾部日志
        if strcmpi(level, 'WARN') || strcmpi(level, 'ERROR')
            flush(LOGFH);
        end
    end
end
