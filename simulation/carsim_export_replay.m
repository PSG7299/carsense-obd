function carsim_export_replay(sim, r, res, batt, file)
%CARSIM_EXPORT_REPLAY Write a replay file the CarSense app can "connect" to.
%   The app's ReplayTransport answers each request with these recorded
%   ELM327 replies, and test/matlab_replay_test.dart checks that the app's
%   verdicts equal the MATLAB verdicts stored under "expected".

pretty = struct('nexon', 'Nexon', 'swift', 'Swift');
f = fieldnames(res.status);
statuses = struct('id', f, 'status', cellfun(@(k) res.status.(k), f, 'UniformOutput', false));

out.format      = 'carsense-replay/1';
out.title       = sprintf('MATLAB sim: %s - %s', pretty.(sim.car), strrep(sim.scenario, '_', ' '));
out.car         = sim.car;
out.scenario    = sim.scenario;
out.description = sim.description;
out.vin         = sim.vin;
out.static      = r.static;
out.series      = r.series;
out.atrv        = r.atrv;
out.atrv_test   = r.atrv_test;
out.expected.statuses = statuses;
out.expected.stored   = sim.dtc_stored;
out.expected.pending  = sim.dtc_pending;
out.expected.score    = res.score;
out.expected.overall  = res.overall;
out.expected.battery  = batt.status;

txt = jsonencode(out);
fid = fopen(file, 'w');
if fid < 0, error('carsim:export', 'Cannot write %s', file); end
fwrite(fid, txt);
fclose(fid);
end
