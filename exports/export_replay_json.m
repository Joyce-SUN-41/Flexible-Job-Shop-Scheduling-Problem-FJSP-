function export_replay_json(frames, path)
% export_replay_json  Stage9: serialize dynamic-replay frame sequence to JSON.
%   frames : struct array from dynamic_replay (time/type/desc/schedule).
%   path   : output .json. Pure serialization; safe, no solver numeric change.
% All field names ASCII English.

    if nargin < 2 || isempty(path)
        path = fullfile(pwd, ['replay_' datestr(now,'yyyy_mm_dd_HH_MM_SS') '.json']);
    end

    out = struct();
    out.version = '1.0';
    out.kind = 'dynamic_replay';
    out.generated = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    nF = numel(frames);
    % Build frames as a STRUCT ARRAY (not a cell) so jsonencode emits a flat JSON
    % array [obj,obj,...] instead of a doubly-nested [[obj],[obj],...].
    frames_out = struct('time', cell(1,nF), 'type', cell(1,nF), ...
                         'desc', cell(1,nF), 'schedule', cell(1,nF), ...
                         'makespan', cell(1,nF));
    for q = 1:nF
        f = frames(q);
        rows = f.schedule;   % cell array of [job,op,machine,start,finish,duration]
        rowCells = cell(1, numel(rows));
        for r = 1:numel(rows)
            rowCells{r} = rows{r}(:).';
        end
        frames_out(q).time = f.time;
        frames_out(q).type = f.type;
        frames_out(q).desc = f.desc;
        frames_out(q).schedule = rowCells;
        % Stage4: carry the per-frame makespan (set by dynamic_replay for the
        % static-vs-dynamic comparison view) when present; otherwise leave empty
        % so the dashboard falls back to max(finish).
        if isfield(f, 'makespan') && isscalar(f.makespan) && isfinite(f.makespan)
            frames_out(q).makespan = f.makespan;
        end
    end
    out.frames = frames_out;

    fid = fopen(path, 'w');
    if fid < 0, error('export_replay_json: cannot open %s', path); end
    try
        fwrite(fid, jsonencode(out, 'PrettyPrint', true), 'char');
    catch ME
        fclose(fid); rethrow(ME);
    end
    fclose(fid);
    fprintf('  [Stage9] exported replay JSON -> %s (%d frames)\n', path, nF);
end
