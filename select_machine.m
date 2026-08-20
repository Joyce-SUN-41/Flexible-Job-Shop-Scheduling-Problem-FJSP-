%% select_machine.m — 机器选择单一入口（阶段4：消除重复机器选择逻辑）
% 在工件 j 的第 k 道工序的可选机器集 prob.op_mach{j}{k} 中，
% 按索引 idx 安全选取机器号；idx 越界时钳制到 [1, nM] 并返回对应机器。
% decode_X（X 潜力场映射）与 refine_elite（索引穷举）共用此函数，
% 保证"索引 -> 机器号"语义在多处完全一致，避免重复钳制分支漂移。
%
% 输入：
%   prob : 问题实例
%   j    : 工件号（1..nJob）
%   k    : 工序序号（1..nOpPerJob(j)）
%   idx  : 机器索引（可能来自 X 映射或穷举计数器，允许越界，内部钳制）
% 输出：
%   m    : 实际机器号（scalar，属于 prob.op_mach{j}{k}）
%   mIdx : 钳制后的合法索引（1..nM）

function [m, mIdx] = select_machine(prob, j, k, idx)
    machSet = prob.op_mach{j}{k};
    nM = length(machSet);
    mIdx = min(max(idx, 1), nM);   % 安全钳制，防止越界
    m = machSet(mIdx);
end
