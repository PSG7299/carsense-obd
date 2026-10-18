function r = carsim_replies(sim)
%CARSIM_REPLIES Turn a simulation into the exact text an ELM327 adapter
%   would send back for each request (CAN 11-bit, headers on, spaces off).
%
%   r.static   - struct array {cmd, reply} for one-off requests
%   r.series   - struct array {cmd, replies{1..300}} for live PIDs
%   r.atrv     - ATRV replies during the scan (engine running)
%   r.atrv_test- ATRV replies for the battery/cranking test (0.1 s steps)

p = sim.profile;
S = sim.scan;
N = numel(S.RPM);

% ---- live PIDs: channel field per PID
map = {'04','LOAD'; '05','ECT'; '06','STFT1'; '07','LTFT1'; '0B','MAP'; '0C','RPM'; ...
       '0D','VSS'; '0E','TIMING'; '0F','IAT'; '11','TPS'; '14','O2V_B1S1'; '15','O2V_B1S2'; ...
       '1F','RUNTIME'; '21','DIST_MIL'; '2F','FUEL_LVL'; '31','DIST_CLR'; '33','BARO'; ...
       '3C','CAT_B1S1'; '42','ECU_V'; '46','AMBIENT'; '49','APP_D'};
series = struct('cmd', {}, 'replies', {});
for i = 1:size(map, 1)
  pid = hex2dec(map{i, 1});
  if ~any(p.pids == pid), continue; end
  x = S.(map{i, 2});
  rep = cell(1, N);
  for k = 1:N
    if pid == 20                       % 0x14 front O2: volts + trim
      v = [x(k) S.O2T_B1S1(k)];
    elseif pid == 21                   % 0x15 rear O2: volts only
      v = [x(k) NaN];
    else
      v = x(k);
    end
    rep{k} = elm_frame([65 pid obd_encode(pid, v)]);   % 0x41 = mode 01 reply
  end
  series(end+1) = struct('cmd', ['01' map{i, 1}], 'replies', {rep}); %#ok<AGROW>
end

% ---- one-off requests
st = struct('cmd', {}, 'reply', {});
add = @(st, cmd, payload) [st struct('cmd', cmd, 'reply', elm_frame(payload))];
for base = [0 32 64]
  mask = zeros(1, 4);
  for k = 1:32
    pid = base + k;
    on = any(p.pids == pid) || (k == 32 && any(p.pids > base + 32));
    if on
      mask(ceil(k / 8)) = mask(ceil(k / 8)) + 2^(7 - mod(k - 1, 8));
    end
  end
  if base == 0 || any(p.pids > base & p.pids <= base + 32)
    st = add(st, sprintf('01%02X', base), [hex2dec('41') base mask]);
  end
end
A = double(sim.mil) * 128 + numel(sim.dtc_stored);
st = add(st, '0101', [hex2dec('41') 1 A 7 sim.mon_supported sim.mon_incomplete]);
st = add(st, '0103', [hex2dec('41') 3 sim.fuelsys 0]);
st = add(st, '0113', [hex2dec('41') hex2dec('13') 3]);
st = add(st, '011C', [hex2dec('41') hex2dec('1C') 6]);
st = add(st, '03', [hex2dec('43') dtc_payload(sim.dtc_stored)]);
st = add(st, '07', [hex2dec('47') dtc_payload(sim.dtc_pending)]);
st = add(st, '0A', [hex2dec('4A') 0]);
st = add(st, '0902', [hex2dec('49') 2 1 double(sim.vin)]);

r.static = st;
r.series = series;
r.atrv = arrayfun(@(v) sprintf('%.1fV', v), S.BATT(:)', 'UniformOutput', false);
r.atrv_test = arrayfun(@(v) sprintf('%.1fV', v), sim.battery_test(:, 2)', 'UniformOutput', false);
end

function b = dtc_payload(codes)
b = numel(codes);
for i = 1:numel(codes)
  b = [b dtc_codec(codes{i})]; %#ok<AGROW>
end
end
