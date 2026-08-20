%% critical_block_neighborhood.m — 关键块邻域统一入口（阶段4：消除重复解码逻辑）
% 给定已解码的 sched 与关键机器 critMach，返回该机器上的有序工序序列 onM
% （schedule 元素数组，按解码顺序排列），供 llm_guided_local_search 与
% refine_elite 共享"真实关键路径 + 关键机器同机工序邻域"逻辑，避免各自重复
% 解码与 loc_of 定位。
%
% 输入：
%   prob     : 问题实例（仅用于维度一致性，当前未强制使用）
%   sched    : decode 返回的 schedule 结构体数组（字段含 machine）
%   critMach : 关键机器号（由 critical_path 反推或 LLM 指定）
% 输出：
%   onM      : 关键机器上的工序序列（schedule 元素），空数组表示无邻域可用
%   locs     : onM 中各工序在 chrom.OS/MS 中的全局位置（经 loc_of 定位）

function [onM, locs] = critical_block_neighborhood(prob, sched, critMach)
    onM = sched([sched.machine] == critMach);
    locs = [];
    if isempty(onM), return; end
    % 统一通过 loc_of 定位全局序号（与 llm_guided_local_search / refine_elite 一致）
    locs = zeros(1, numel(onM));
    for q = 1:numel(onM)
        locs(q) = loc_of(sched, onM(q));
    end
end
