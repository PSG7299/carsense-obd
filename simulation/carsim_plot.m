function carsim_plot(sim, data, res, batt, file)
%CARSIM_PLOT Six-panel overview of one simulated scenario, saved as PNG.

fig = figure('visible', 'off', 'position', [0 0 1500 900]);
green = [0.18 0.49 0.20]; red = [0.78 0.16 0.16]; blue = [0.08 0.40 0.75]; orange = [0.98 0.55 0];
tm = sim.t / 60;

subplot(2, 3, 1);
fill([0 20 20 0], [82 82 105 105], green, 'facealpha', 0.12, 'edgecolor', 'none'); hold on;
plot(tm, sim.full.ECT, 'color', red, 'linewidth', 1.5);
xlabel('time since cold start (min)'); ylabel('C'); title('Coolant temperature (green = normal)');
xlim([0 20]); ylim([20 130]); grid on;

subplot(2, 3, 2);
plot(sim.scan_t - sim.scan_t(1), data.ch.RPM, 'color', blue); grid on;
xlabel('scan time (s)'); ylabel('rpm');
title(sprintf('Idle speed  (mean %.0f, sd %.0f rpm)', mean(data.ch.RPM), std(data.ch.RPM, 1)));
ylim([400 1200]);

subplot(2, 3, 3);
k = 1:100;
plot((k - 1) * 0.1, data.ch.O2V_B1S1(k), 'color', orange, 'linewidth', 1.5); hold on;
plot((k - 1) * 0.1, data.ch.O2V_B1S2(k), 'color', blue, 'linewidth', 1.5);
legend('front O2 (B1S1)', 'rear O2 (B1S2)', 'location', 'southoutside', 'orientation', 'horizontal');
xlabel('scan time (s)'); ylabel('V'); ylim([0 1]); grid on;
title('O2 sensors (front should switch, rear steady)');

subplot(2, 3, 4);
plot(tm, sim.full.STFT1, 'color', [0.6 0.6 0.6]); hold on;
plot(tm, sim.full.LTFT1, 'color', [0.56 0.14 0.67], 'linewidth', 2);
plot([0 20], [10 10], 'k--', [0 20], [-10 -10], 'k--');
legend('short-term', 'long-term', 'location', 'southoutside', 'orientation', 'horizontal');
xlabel('time since cold start (min)'); ylabel('%'); xlim([0 20]); ylim([-25 25]); grid on;
title('Fuel trims (+ = adding fuel / lean)');

subplot(2, 3, 5);
tb = data.battery_trace(:, 1); vb = data.battery_trace(:, 2);
fill([0 20 20 0], [13.2 13.2 14.8 14.8], green, 'facealpha', 0.12, 'edgecolor', 'none'); hold on;
fill([0 20 20 0], [8 8 9.6 9.6], red, 'facealpha', 0.12, 'edgecolor', 'none');
plot(tb, vb, 'color', orange, 'linewidth', 1.5);
xlabel('s'); ylabel('V'); ylim([8 16]); grid on;
title(sprintf('Battery test: rest %.1f, crank %.1f, charge %.1f V -> %s', batt.rest, batt.crank, batt.charging, upper(batt.status)));

subplot(2, 3, 6); axis off;
f = fieldnames(res.status);
lines = {sprintf('%s  |  %s', sim.profile.name, strrep(sim.scenario, '_', ' ')), ...
         sprintf('Health score: %d / 100  (%s)', res.score, upper(res.overall)), ...
         sprintf('Stored DTCs: %s', join_or_none(sim.dtc_stored)), ...
         sprintf('Pending DTCs: %s', join_or_none(sim.dtc_pending)), ''};
for i = 1:numel(f)
  st = res.status.(f{i});
  if any(strcmp(st, {'warn', 'fail'}))
    lines{end+1} = sprintf('%s: %s  %s', upper(st), f{i}, res.message.(f{i})); %#ok<AGROW>
  end
end
if numel(lines) == 5, lines{end+1} = 'All sensors within normal ranges'; end
text(0, 1, lines, 'verticalalignment', 'top', 'fontsize', 11, 'interpreter', 'none');

print(fig, '-dpng', '-r80', file);
close(fig);
end

function s = join_or_none(c)
if isempty(c), s = 'none'; else, s = strjoin(c, ', '); end
end
