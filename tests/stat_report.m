function S = stat_report(R, varargin)
% stat_report  Summarize experiment_runs results with descriptive stats and a
%              Wilcoxon rank-sum (Mann-Whitney U) significance test, the standard
%              convention for comparing meta-heuristic algorithms in TEVC-class papers.
%
%   S = stat_report(R, 'Compare', {'aoo','random'})
%
% Computes, per variant:
%   mean, std, median, min (best), max, 95% confidence interval of the mean.
% Then performs pairwise Wilcoxon rank-sum between the first variant and each other
% variant on makespan. p < 0.05 is reported as significant.
%
% SAFE / ADDITIVE: analysis only; no solver modification.

    p = inputParser;
    addParameter(p, 'Compare', fieldnames(R.mk), @iscell);
    parse(p, varargin{:});
    cmp = p.Results.Compare;

    S = struct();
    S.variants = cmp;
    S.N = R.N;
    S.nEval = R.nEval;
    S.desc = struct();
    S.test = struct();

    variants = fieldnames(R.mk);
    for c = 1:numel(cmp)
        v = cmp{c};
        if ~ismember(v, variants)
            warning('stat_report:missing', 'Variant %s not in results; skipped.', v);
            continue;
        end
        x = R.mk.(v);
        d.mean = mean(x);
        d.std = std(x);
        d.median = median(x);
        d.best = min(x);
        d.worst = max(x);
        ci = 1.96 * std(x) / sqrt(numel(x));   % 95% CI of the mean
        d.ci_lo = d.mean - ci;
        d.ci_hi = d.mean + ci;
        S.desc.(v) = d;
        disp(['Variant ', v, ' : mean=', num2str(d.mean, '%.2f'), ...
            ' std=', num2str(d.std, '%.2f'), ' median=', num2str(d.median, '%.1f'), ...
            ' best=', num2str(d.best, '%.1f'), ' [95%CI ', num2str(d.ci_lo, '%.2f'), ...
            ',', num2str(d.ci_hi, '%.2f'), ']']);
    end

    % Pairwise Wilcoxon rank-sum of makespan: baseline (first) vs others.
    base = cmp{1};
    if ismember(base, variants)
        x0 = R.mk.(base);
        for c = 2:numel(cmp)
            v = cmp{c};
            if ~ismember(v, variants), continue; end
            x1 = R.mk.(v);
            [pval, h] = ranksum(x1, x0);
            % Effect size (rank-biserial correlation) for Wilcoxon.
            rbc = (2 * (ranksum(x1, x0) - numel(x1) * (numel(x1) + numel(x0) + 1) / 2)) ...
                / (numel(x1) * numel(x0));
            S.test.(v) = struct('p', pval, 'significant', h == 1, 'rank_biserial', rbc, ...
                'mean_improve_pct', 100 * (mean(x0) - mean(x1)) / mean(x0));
            sigStr = 'SIGNIFICANT';
            if h ~= 1, sigStr = 'not significant'; end
            disp(['Wilcoxon ', v, ' vs ', base, ' : p=', num2str(pval, '%.4g'), ...
                ' -> ', sigStr, ' | mean improvement=', num2str(S.test.(v).mean_improve_pct, '%.1f'), ...
                '% | r_biserial=', num2str(rbc, '%.3f')]);
        end
    end
end
