function res = carsim_diagnose(data, p)
%CARSIM_DIAGNOSE Independent MATLAB implementation of the CarSense health
%   rules (lib/diagnostics/health_engine.dart). Given decoded readings it
%   rates each sensor 'ok' / 'info' / 'warn' / 'fail' and computes the
%   0-100 health score, so the app's verdicts can be cross-checked.
%
%   res.status.<CHANNEL>, res.message.<CHANNEL>, res.score, res.overall

ch = data.ch;
if p.turbo && isfield(ch, 'MAP') && isfield(ch, 'BARO')
  ch.BOOST = ch.MAP - mean(ch.BARO);
end
c.running = mean(ch.RPM) > 400;
c.warm    = mean(ch.ECT) >= 70;
c.closed  = data.fuelsys == 2 || data.fuelsys == 16;
c.idling  = c.running && mean(ch.VSS) < 3 && max(ch.RPM) < 1600;
c.ch = ch;  c.p = p;

res.status = struct();  res.message = struct();
f = fieldnames(ch);
warn = 0; fail = 0;
for i = 1:numel(f)
  [st, msg] = rate_channel(c, f{i}, ch.(f{i}));
  res.status.(f{i}) = st;
  res.message.(f{i}) = msg;
  warn = warn + strcmp(st, 'warn');
  fail = fail + strcmp(st, 'fail');
end

% ---- score (same weights as the app)
score = 100 - 4 * warn - 12 * fail;
score = score - 5 * numel(data.pending);
for i = 1:numel(data.stored)
  switch dtc_severity(data.stored{i})
    case 'high',   score = score - 20;
    case 'medium', score = score - 12;
    otherwise,     score = score - 5;
  end
end
if data.mil, score = score - 10; end
score = score - min(8, 2 * data.mon_incomplete);
res.score = min(max(round(score), 0), 100);
if res.score >= 80,     res.overall = 'ok';
elseif res.score >= 55, res.overall = 'warn';
else,                   res.overall = 'fail';
end
res.context = rmfield(c, {'ch', 'p'});
end

% ------------------------------------------------------------------------
function [st, msg] = rate_channel(c, id, s)
v = mean(s);
lim = struct('ECT', [-40 215], 'IAT', [-40 215], 'AMBIENT', [-40 215], ...
             'MAP', [0 255], 'TPS', [0 100], 'APP_D', [0 100]);
if isfield(lim, id)
  L = lim.(id);
  if all(s <= L(1) + 0.01) || all(s >= L(2) - 0.01)
    st = 'fail'; msg = 'stuck at limit (open/short circuit)'; return;
  end
end
p = c.p;
switch id
  case 'RPM'
    if ~c.running, st = 'info'; msg = 'engine off'; return; end
    if ~c.idling,  st = 'ok';   msg = 'running'; return; end
    if ~c.warm,    st = 'info'; msg = 'fast idle while warming up'; return; end
    st = rate(v, p.idle_ok, p.idle_warn);
    if std(s, 1) > 80, st = worst('warn', st); msg = 'unsteady idle'; else, msg = 'idle'; end
  case 'ECT'
    if v > p.coolant_warn(2),     st = 'fail'; msg = 'overheating';
    elseif v > p.coolant_ok(2),   st = 'warn'; msg = 'running hot';
    elseif ~c.running,            st = 'ok';   msg = 'plausible';
    elseif mean(c.ch.RUNTIME) > 900 && v < p.coolant_warn(1)
                                  st = 'warn'; msg = 'thermostat stuck open?';
    elseif v < p.coolant_ok(1),   st = 'info'; msg = 'warming up';
    else,                         st = 'ok';   msg = 'normal';
    end
  case 'IAT'
    if v > 75, st = 'warn'; else, st = 'ok'; end, msg = '';
  case 'AMBIENT'
    st = 'ok'; msg = '';
  case 'MAP'
    if ~c.running
      ref = 98; if isfield(c.ch, 'BARO'), ref = mean(c.ch.BARO); end
      if abs(v - ref) > 10, st = 'warn'; else, st = 'ok'; end
    elseif ~c.idling, st = 'ok';
    else, st = rate(v, p.map_ok, p.map_warn);
    end
    msg = '';
  case 'BARO'
    st = rate(v, [60 106], [50 110]); msg = '';
  case 'BOOST'
    mx = max(s);
    if mx > p.max_boost + 30, st = 'warn'; elseif mx < 5, st = 'info'; else, st = 'ok'; end
    msg = '';
  case 'TPS'
    if c.idling && v > 30, st = 'warn'; else, st = 'ok'; end, msg = '';
  case 'APP_D'
    if ~c.running || c.idling
      if v < 25, st = 'ok'; else, st = 'warn'; end
    else, st = 'ok';
    end
    msg = '';
  case {'STFT1', 'LTFT1'}
    if ~c.running || ~c.closed, st = 'info'; msg = 'trims inactive'; return; end
    a = abs(v);
    if a <= 10, st = 'ok'; elseif a <= 20, st = 'warn'; else, st = 'fail'; end
    if v > 0, msg = 'lean'; else, msg = 'rich'; end
  case {'O2V_B1S1', 'O2V_B1S2'}
    [st, msg] = rate_o2(c, id, s);
  case 'CAT_B1S1'
    st = rate(v, [-40 900], [-inf 1000]); msg = '';
  case {'BATT', 'ECU_V'}
    if c.running
      st = rate(v, [13.2 14.8], [12.6 15.0]);
    elseif v > 13.0
      st = 'ok';
    else
      st = rate(v, [12.4 13.0], [12.0 13.4]);
    end
    msg = '';
  case 'LOAD'
    if ~c.idling || ~c.warm, st = 'info'; elseif v > 50, st = 'warn'; else, st = 'ok'; end, msg = '';
  case 'TIMING'
    if ~c.idling || ~c.warm, st = 'info'; elseif v < -2, st = 'warn'; else, st = 'ok'; end, msg = '';
  case 'FUEL_LVL'
    if v < 10, st = 'warn'; else, st = 'ok'; end, msg = '';
  case 'DIST_MIL'
    if v > 0, st = 'warn'; else, st = 'ok'; end, msg = '';
  otherwise
    st = 'info'; msg = '';
end
end

function [st, msg] = rate_o2(c, id, s)
if ~c.running, st = 'info'; msg = 'engine off'; return; end
if ~c.warm || ~c.closed, st = 'info'; msg = 'not tested yet'; return; end
mn = min(s); mx = max(s); avg = mean(s);
sw = carsim_crossings(s, 0.45);
if strcmp(id, 'O2V_B1S1')
  if mx - mn < 0.3
    st = 'fail';
    if avg < 0.25, msg = 'stuck lean'; elseif avg > 0.75, msg = 'stuck rich'; else, msg = 'no activity'; end
  elseif sw < 2
    st = 'warn'; msg = 'slow response';
  else
    st = 'ok'; msg = sprintf('switching (%d)', sw);
  end
else
  up = carsim_crossings(c.ch.O2V_B1S1, 0.45);
  if mx < 0.2
    st = 'warn'; msg = 'reads lean constantly';
  elseif up >= 4 && sw >= up * 0.75
    st = 'warn'; msg = 'catalyst efficiency low';
  else
    st = 'ok'; msg = 'steady - catalyst working';
  end
end
end

function st = rate(v, ok, wr)
if v >= ok(1) && v <= ok(2), st = 'ok';
elseif v < ok(1)
  if v >= wr(1), st = 'warn'; else, st = 'fail'; end
else
  if v <= wr(2), st = 'warn'; else, st = 'fail'; end
end
end

function w = worst(a, b)
order = {'ok', 'info', 'warn', 'fail'};
if find(strcmp(order, a)) >= find(strcmp(order, b)), w = a; else, w = b; end
end

function s = dtc_severity(code)
high = {'P0217', 'P0219', 'P0234', 'P0335', 'P0520', 'P0562', 'P0563', 'P0601', 'P0606', 'U0100'};
if ~isempty(regexp(code, '^P030[0-9]$', 'once')) || any(strcmp(high, code))
  s = 'high';
elseif ~isempty(regexp(code, '^P04[45]', 'once')) || any(strcmp({'P0603', 'P0650'}, code))
  s = 'low';
else
  s = 'medium';
end
end
