function evt = perturbation(prob, t, type, varargin)
% perturbation dynamic event generator (Stage8 dynamic rescheduling core)
%   'machine_breakdown' : machine m down for dur steps at time t
%   'urgent_insert'     : new job inserted at time t
%   'job_delay'         : job j release delayed by dur at time t
% Returns evt struct consumed by aoo_engine dynamic loop. Safe: only describes,
% never mutates prob or population.

    p = inputParser;
    addParameter(p,'machine',[],@isscalar);
    addParameter(p,'dur',ceil(prob.nMachine*1.5),@isscalar);
    addParameter(p,'job',[],@isscalar);
    addParameter(p,'newjob_ops',3,@isscalar);
    parse(p,varargin{:});

    evt = struct();
    evt.time = t;
    evt.type = type;

    switch lower(type)
        case 'machine_breakdown'
            if isempty(p.Results.machine)
                m = randi(prob.nMachine);
            else
                m = p.Results.machine;
            end
            evt.machine = m;
            evt.dur = p.Results.dur;
            evt.desc = sprintf('machine %d down at t=%g for %g steps', m, t, evt.dur);
        case 'urgent_insert'
            nj = prob.nJob + 1;
            evt.new_job = nj;
            evt.ops = p.Results.newjob_ops;
            evt.desc = sprintf('urgent job #%d inserted at t=%g (ops=%d)', nj, t, evt.ops);
        case 'job_delay'
            if isempty(p.Results.job)
                j = randi(prob.nJob);
            else
                j = p.Results.job;
            end
            evt.job = j;
            evt.delay = p.Results.dur;
            evt.desc = sprintf('job %d delayed at t=%g by %g steps', j, t, evt.delay);
        otherwise
            error('perturbation: unknown event type "%s"', type);
    end
end

function violated = evt_violates(evt, schedule)
    violated = false;
    if ~isfield(schedule,'machine') || ~isfield(schedule,'start') ...
            || ~isfield(schedule,'finish')
        return;
    end
    switch lower(evt.type)
        case 'machine_breakdown'
            m = evt.machine;
            for i=1:length(schedule.machine)
                if schedule.machine(i)==m && ...
                   schedule.start(i) < evt.time + evt.dur && ...
                   schedule.finish(i) > evt.time
                    violated = true; return;
                end
            end
        case 'urgent_insert'
            violated = true;
        case 'job_delay'
            violated = true;
        otherwise
            % nothing
    end
end
