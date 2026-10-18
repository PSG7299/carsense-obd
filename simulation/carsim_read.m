function data = carsim_read(r)
%CARSIM_READ Act as the app: parse every ELM327 reply produced by
%   carsim_replies and decode it back to physical values. Diagnosing these
%   values (instead of the raw simulation) tests the whole encode -> frame
%   -> parse -> decode path, including the quantisation the app sees.

data.ch = struct();
for i = 1:numel(r.series)
  pid = hex2dec(r.series(i).cmd(3:4));
  reps = r.series(i).replies;
  for k = 1:numel(reps)
    pl = elm_parse(reps{k});
    assert(pl(1) == 65 && pl(2) == pid, 'reply/PID mismatch');
    [v, id] = obd_decode(pid, pl(3:end));
    data.ch.(id)(k, 1) = v;
  end
end
data.ch.BATT = cellfun(@(s) sscanf(s, '%fV'), r.atrv(:));
data.battery_trace = [(0:numel(r.atrv_test) - 1)' * 0.1, cellfun(@(s) sscanf(s, '%fV'), r.atrv_test(:))];

get = @(cmd) elm_parse(r.static(strcmp({r.static.cmd}, cmd)).reply);
fs = get('0103');            data.fuelsys = fs(3);
mon = get('0101');
data.mil = mon(3) >= 128;
data.mon_incomplete = sum(bitget(bitand(mon(6), mon(5)), 1:8));
data.stored  = dtc_list(get('03'));
data.pending = dtc_list(get('07'));
vin = get('0902');           data.vin = char(vin(4:end));
end

function c = dtc_list(pl)
c = {};
for i = 3:2:numel(pl) - 1
  if pl(i) == 0 && pl(i + 1) == 0, continue; end
  c{end+1} = dtc_codec(pl(i:i + 1)); %#ok<AGROW>
end
end
