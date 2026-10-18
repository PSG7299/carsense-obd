function b = carsim_battery_eval(trace)
%CARSIM_BATTERY_EVAL Rate a battery/cranking voltage trace [t V] the same
%   way as HealthEngine.analyseBattery in the app.
%   b.rest, b.crank (median voltage while cranking), b.charging, b.status ('ok'|'warn'|'fail'|'info')

v = trace(:, 2)';
b = struct('rest', NaN, 'crank', NaN, 'charging', NaN, 'status', 'info');
if numel(v) < 5, return; end
[~, mi] = min(v);                       % first minimum (1-based)
before = v(1:max(1, min(mi - 1, 10)));
b.rest = upper_median(before);
% Cranking voltage = median of the dip, so a single starter-inrush sample
% does not decide the verdict.
dip = v(v < b.rest - 1.0);
cranked = ~isempty(dip);
if cranked, crank = upper_median(dip); end
if cranked, after = v(mi:end); else, after = v; end
tail = after(max(1, end - 14):end);
charging = upper_median(tail);
started = cranked && numel(after) >= 5;

st = 'ok';
if b.rest < 12.0, st = worst(st, 'fail'); elseif b.rest < 12.4, st = worst(st, 'warn'); end
if cranked
  b.crank = crank;
  if crank < 9.0, st = worst(st, 'fail'); elseif crank < 9.6, st = worst(st, 'warn'); end
end
if started
  b.charging = charging;
  if charging > 15.0 || charging < 12.6, st = worst(st, 'fail');
  elseif charging < 13.2, st = worst(st, 'warn');
  end
end
b.status = st;
end

function m = upper_median(x)
x = sort(x);
m = x(floor(numel(x) / 2) + 1);
end

function w = worst(a, b)
order = {'ok', 'info', 'warn', 'fail'};
if find(strcmp(order, a)) >= find(strcmp(order, b)), w = a; else, w = b; end
end
