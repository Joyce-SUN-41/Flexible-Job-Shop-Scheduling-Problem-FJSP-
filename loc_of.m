function idx = loc_of(sched, elem)
    % SAFE FIX (2026-08-14): callers pass EITHER a schedule struct (critical_block_
    % neighborhood) OR an integer index already resolved by critical_path (cp vector).
    % When elem is a numeric scalar, it is already the global position -> return as-is.
    if isscalar(elem) && isnumeric(elem)
        idx = round(elem);
        return;
    end
    for i=1:numel(sched)
        if sched(i).job==elem.job && sched(i).op==elem.op && sched(i).machine==elem.machine
            idx=i; return; end
    end
    idx = 1;
end
