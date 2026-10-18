function run_tests()
%RUN_TESTS Test suite for the CarSense car simulation (MATLAB or Octave).
%   From the simulation folder:  addpath('tests'); run_tests
%   Throws an error (non-zero exit) if any test fails.

here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, '..'));

tests = {@t_obd_codec_roundtrip, @t_dtc_codec, @t_elm_framing, @t_elm_matches_app_vector, ...
         @t_physics_healthy, @t_scenario_verdicts, @t_battery_eval, @t_determinism, ...
         @t_replies_cover_supported_pids};
failed = 0;
for i = 1:numel(tests)
  name = func2str(tests{i});
  try
    tests{i}();
    fprintf('  PASS  %s\n', name);
  catch err
    failed = failed + 1;
    fprintf('  FAIL  %s\n        %s\n', name, err.message);
  end
end
fprintf('\n%d of %d tests passed\n', numel(tests) - failed, numel(tests));
if failed > 0
  error('carsim:tests', '%d test(s) failed', failed);
end
end

% ------------------------------------------------------------------ tests

function t_obd_codec_roundtrip()
% value -> bytes -> value must agree to within one quantisation step
cases = {'04', 0:7:100, 100/255; '05', -40:13:215, 1; '06', -100:9:99, 100/128; ...
         '0B', 0:17:255, 1; '0C', 0:250:16000, 0.25; '0E', -64:7:63, 0.5; ...
         '11', 0:9:100, 100/255; '1F', 0:5000:65000, 1; '3C', -40:300:6000, 0.1; '42', 0:0.7:65, 0.001};
for i = 1:size(cases, 1)
  pid = hex2dec(cases{i, 1});
  for v = cases{i, 2}
    b = obd_encode(pid, v);
    assert(all(b >= 0 & b <= 255), 'byte out of range');
    back = obd_decode(pid, b);
    assert(abs(back - v) <= cases{i, 3} / 2 + 1e-9, sprintf('PID %s: %g -> %g', cases{i, 1}, v, back));
  end
end
b = obd_encode(hex2dec('14'), [0.45 NaN]);
assert(isequal(b, [90 255]), 'O2 sensor bytes');
end

function t_dtc_codec()
pairs = {'P0420', [4 32]; 'P0171', [1 113]; 'C0420', [68 32]; 'B1234', [146 52]; 'U0100', [193 0]};
for i = 1:size(pairs, 1)
  assert(isequal(dtc_codec(pairs{i, 1}), pairs{i, 2}), ['encode ' pairs{i, 1}]);
  assert(strcmp(dtc_codec(pairs{i, 2}), pairs{i, 1}), ['decode ' pairs{i, 1}]);
end
end

function t_elm_framing()
single = elm_frame([65 5 123]);
assert(strcmp(single, '7E80341057B'), single);
assert(isequal(elm_parse([single char(13) char(13) '>']), [65 5 123]), 'parse single');
long = [73 2 1 double('MAT627108NLK12345')];
txt = elm_frame(long);
assert(numel(strsplit(txt, char(13))) == 3, 'VIN should be 3 CAN frames');
assert(isequal(elm_parse(txt), long), 'parse multi-frame');
assert(isempty(elm_parse('NO DATA\r>')), 'NO DATA');
end

function t_elm_matches_app_vector()
% Same VIN frames as test/parser_test.dart in the app.
expected = ['7E810144902014D4154' char(13) '7E8213632373130384E' char(13) '7E8224C4B3132333435'];
got = elm_frame([73 2 1 double('MAT627108NLK12345')]);
assert(strcmp(got, expected), 'frames differ from the app test vector');
end

function t_physics_healthy()
for car = {'nexon', 'swift'}
  s = carsim_simulate(car{1}, 'healthy', 3);
  assert(s.full.ECT(end) > 85 && s.full.ECT(end) < 95, 'warm coolant 85-95 C');
  assert(s.full.ECT(1) < 35, 'cold start');
  assert(s.full.CLOSED(end) == 1 && s.full.CLOSED(1) == 0, 'open -> closed loop');
  assert(carsim_crossings(s.scan.O2V_B1S1, 0.45) >= 10, 'front O2 switching');
  assert(carsim_crossings(s.scan.O2V_B1S2, 0.45) == 0, 'rear O2 steady');
  assert(abs(mean(s.scan.LTFT1)) < 5, 'small long-term trim');
  assert(abs(mean(s.full.LAMBDA(end-299:end)) - 1) < 0.02, 'lambda ~1');
  assert(isempty(s.dtc_stored) && isempty(s.dtc_pending), 'no DTCs');
end
end

function t_scenario_verdicts()
% scenario -> {channel, expected status; ...}, stored, pending, battery status
spec = {
  'healthy',          {},                                  {},        {},        'ok'
  'vacuum_leak',      {'LTFT1', 'warn'},                   {},        {'P0171'}, 'ok'
  'worn_catalyst',    {'O2V_B1S2', 'warn'},                {'P0420'}, {},        'ok'
  'dead_o2_sensor',   {'O2V_B1S1', 'fail'},                {'P0134'}, {},        'ok'
  'stuck_thermostat', {'ECT', 'warn'},                     {},        {'P0128'}, 'ok'
  'overheating',      {'ECT', 'fail'},                     {'P0217'}, {},        'ok'
  'misfire',          {'RPM', 'warn'},                     {'P0301'}, {},        'ok'
  'weak_battery',     {'BATT', 'ok'},                      {},        {},        'warn'
  'alternator_fault', {'BATT', 'fail'; 'ECU_V', 'fail'},   {'P0562'}, {},        'fail'
};
for car = {'nexon', 'swift'}
  for i = 1:size(spec, 1)
    sim  = carsim_simulate(car{1}, spec{i, 1}, 1);
    data = carsim_read(carsim_replies(sim));
    res  = carsim_diagnose(data, sim.profile);
    batt = carsim_battery_eval(data.battery_trace);
    tag = [car{1} '/' spec{i, 1}];
    exp_ch = spec{i, 2};
    for k = 1:size(exp_ch, 1)
      got = res.status.(exp_ch{k, 1});
      assert(strcmp(got, exp_ch{k, 2}), sprintf('%s: %s is %s, expected %s', tag, exp_ch{k, 1}, got, exp_ch{k, 2}));
    end
    % Every channel not named above must be ok/info (no false alarms).
    f = fieldnames(res.status);
    for k = 1:numel(f)
      if any(strcmp(exp_ch(:), f{k})), continue; end
      assert(any(strcmp(res.status.(f{k}), {'ok', 'info'})), sprintf('%s: false alarm on %s (%s)', tag, f{k}, res.status.(f{k})));
    end
    assert(isequal(sort(data.stored), sort(spec{i, 3})), sprintf('%s: stored DTCs [%s]', tag, strjoin(data.stored, ',')));
    assert(isequal(sort(data.pending), sort(spec{i, 4})), sprintf('%s: pending DTCs [%s]', tag, strjoin(data.pending, ',')));
    assert(strcmp(batt.status, spec{i, 5}), sprintf('%s: battery %s', tag, batt.status));
    assert(data.mil == ~isempty(spec{i, 3}), [tag ': MIL']);
    assert(strcmp(data.vin, sim.vin), [tag ': VIN']);
    if strcmp(spec{i, 1}, 'healthy')
      assert(res.score >= 90, sprintf('%s: score %d', tag, res.score));
    else
      % Every fault must show up in the scan score or in the battery test.
      assert(res.score < 100 || ~strcmp(batt.status, 'ok'), sprintf('%s: fault not detected', tag));
    end
  end
end
end

function t_battery_eval()
mk = @(rest, crank, run) [(0:39)' * 0.1, [rest * ones(15, 1); crank * ones(5, 1); run * ones(20, 1)]];
assert(strcmp(carsim_battery_eval(mk(12.6, 10.4, 14.1)).status, 'ok'));
assert(strcmp(carsim_battery_eval(mk(12.2, 9.3, 13.0)).status, 'warn'));
assert(strcmp(carsim_battery_eval(mk(11.7, 8.1, 12.2)).status, 'fail'));
% Dead alternator must be caught even though the charging voltage is
% below the resting voltage.
b = carsim_battery_eval(mk(12.5, 10.6, 12.2));
assert(strcmp(b.status, 'fail') && abs(b.charging - 12.2) < 1e-9, 'dead alternator not detected');
% A single 0.1 s inrush spike must not fail a healthy battery.
tr = mk(12.6, 10.4, 14.1);  tr(16, 2) = 8.7;
b = carsim_battery_eval(tr);
assert(strcmp(b.status, 'ok') && abs(b.crank - 10.4) < 1e-9, 'inrush spike decided the verdict');
end

function t_determinism()
a = carsim_simulate('swift', 'misfire', 7);
b = carsim_simulate('swift', 'misfire', 7);
c = carsim_simulate('swift', 'misfire', 8);
assert(isequal(a.scan.RPM, b.scan.RPM), 'same seed must give same result');
assert(~isequal(a.scan.RPM, c.scan.RPM), 'different seed should differ');
end

function t_replies_cover_supported_pids()
sim = carsim_simulate('nexon', 'healthy', 1);
r = carsim_replies(sim);
cmds = [{r.series.cmd}, {r.static.cmd}];
for pid = sim.profile.pids
  assert(any(strcmp(cmds, sprintf('01%02X', pid))), sprintf('no reply for PID %02X', pid));
end
mask = elm_parse(r.static(strcmp({r.static.cmd}, '0100')).reply);
assert(bitget(mask(3), 4) == 1, 'PID 05 (coolant) advertised');  % 0x08 = PID 05
end
