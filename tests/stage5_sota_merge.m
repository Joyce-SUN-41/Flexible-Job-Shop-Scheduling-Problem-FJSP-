function stage5_sota_merge()
% stage5_sota_merge  Assemble logs/stage5_sota_compare.json from per-instance files
%   stage5_sota_MKxx.json produced by stage5_sota_full('MKxx') (process-isolated runs).
% SAFE / ADDITIVE: read-only over logs; writes only logs/stage5_sota_compare.json.

    logDir = fullfile(pwd, 'logs');
    insts = {'MK01', 'MK04', 'MK06', 'MK09'};
    variants = {'aoo', 'ga', 'pso', 'alns', 'random'};
    N = 30; Pop = 30; MaxGen = 60;
    alldata = struct();
    for i = 1:numel(insts)
        f = fullfile(logDir, ['stage5_sota_' insts{i} '.json']);
        if ~exist(f, 'file')
            fprintf('  [skip] missing %s\n', f);
            continue;
        end
        d = jsondecode(fileread(f));
        alldata.(insts{i}) = d.data.(insts{i});
        fprintf('  merged %s (aoo best=%.1f)\n', insts{i}, min(d.data.(insts{i}).mk.aoo));
    end
    out = struct();
    out.instances = insts;
    out.variants = variants;
    out.N = N;
    out.budget = sprintf('POP=%d MAXGEN=%d', Pop, MaxGen);
    out.data = alldata;
    cmpPath = fullfile(logDir, 'stage5_sota_compare.json');
    str = jsonencode(out);
    fid = fopen(cmpPath, 'w', 'n', 'UTF-8');
    fwrite(fid, str, 'char');
    fclose(fid);
    fprintf('stage5_sota_compare.json assembled: %s\n', cmpPath);
end
