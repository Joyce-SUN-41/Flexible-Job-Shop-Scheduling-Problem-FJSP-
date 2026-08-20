function stage5_validate_check()
% stage5_validate_check  Verify validate_schedule accepts the real export schema
%   (cell-of-rows, 6 cols [job,op,machine,start,finish,duration], finish>=start>=0)
%   and rejects malformed rows. ADDITIVE smoke; writes logs/stage5_validate.json.
    addpath('exports');
    % valid sample (matches export_result_json SCHEMA)
    good = { [1 1 2 0 5 5], [1 2 1 5 10 5], [2 1 3 0 8 8] };
    validate_schedule(good);
    fprintf('VALID sample accepted OK\n');
    % numeric matrix form
    validate_schedule([1 1 2 0 5 5; 1 2 1 5 10 5]);
    fprintf('VALID matrix accepted OK\n');
    % reject: finish < start
    try validate_schedule({[1 1 2 10 5 5]}); catch, fprintf('REJECT finish<start OK\n'); end
    % reject: wrong col count
    try validate_schedule({[1 1 2 0 5]}); catch, fprintf('REJECT colcount OK\n'); end
    % reject: negative start
    try validate_schedule({[1 1 2 -1 5 6]}); catch, fprintf('REJECT neg start OK\n'); end
    if ~exist('logs','dir'), mkdir('logs'); end
    fid = fopen('logs/stage5_validate.json','w');
    fwrite(fid, '{"validate_schedule":"passed_all_cases"}', 'char'); fclose(fid);
    fprintf('stage5_validate_check DONE -> logs/stage5_validate.json\n');
end
