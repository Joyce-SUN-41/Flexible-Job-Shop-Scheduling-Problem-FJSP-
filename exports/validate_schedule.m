function validate_schedule(rows)
% validate_schedule  Stage5 (E4) schema guard for exported schedule matrix.
%   Enforces the SCHEMA contract declared in export_result_json.m (Stage0 Z4):
%     - every row has exactly 6 columns in fixed order
%       [job, op, machine, start, finish, duration]
%     - finish >= start >= 0  (non-negative, monotonic operation timing)
%     - all entries finite numeric (no NaN/Inf leaking into viz layer)
%   Pure defensive ADDITIVE; throws on violation so stage9_run gate catches it.
%   Zero solver numerics touched; safe for regression gate.

    assert(iscell(rows) || isnumeric(rows), ...
        'schedule must be cell-of-rows or numeric matrix');
    if iscell(rows)
        nRows = numel(rows);
        assert(nRows > 0, 'schedule must have at least one operation row');
        for i = 1:nRows
            r = rows{i};
            validate_row(r, i);
        end
    else
        assert(size(rows, 2) == 6, ...
            sprintf('schedule matrix must have 6 columns, got %d', size(rows, 2)));
        assert(size(rows, 1) > 0, 'schedule must have at least one operation row');
        for i = 1:size(rows, 1)
            validate_row(rows(i, :), i);
        end
    end
end

function validate_row(r, i)
    v = r(:).';
    assert(numel(v) == 6, ...
        sprintf('schedule row %d must have 6 columns, got %d', i, numel(v)));
    assert(all(isfinite(v)), ...
        sprintf('schedule row %d contains non-finite value (NaN/Inf)', i));
    assert(v(4) >= 0 && v(5) >= v(4), ...
        sprintf('schedule row %d violates finish>=start>=0 (start=%.3g finish=%.3g)', ...
                i, v(4), v(5)));
end
